require 'lspace/eventmachine'

# EM::Monitor adds a few methods to eventmachine that can help you
# keep track of 'lag' caused by long-running CPU spans on the reactor thread.
module EventMachine

  class << self
    alias_method :run_without_monitor, :run
    private :run_without_monitor
  end

  # Run the eventmachine reactor with monitoring.
  def self.run(*args, &block)
    run_without_monitor(*args) do |*a, &b|
      EM::Monitor.new do |monitor|
        @em_monitor = monitor
        block.call(*a, &b) if block_given?
      end
    end
  ensure
    @em_monitor = nil
  end

  # Set the block to be called periodically with timing data.
  #
  # @param [Hash] opts  Configuration
  # @param [Proc] block  the block to call.
  #
  # @option opts [Number] :interval (60)
  #   The approximate number of seconds between calls to your block.
  #   If your event loop regularly runs long CPU-spans then the actual time between
  #   calls can vary significantly.
  #
  # @yieldparam [Array<Float>] spans  The number of seconds spent by each CPU-span in the
  #                                   monitoring interval
  # @yieldparam [Time] from  The start of the monitoring interval
  # @yieldparam [Time] to    The end of the monitoring interval
  #
  # @example
  #   EM::monitor_spans do |spans, from, to|
  #     puts "Used %.2f seconds of CPU in the last %.2f seconds." % (spans.inject(&:+), to - from)
  #   end
  def self.monitor_spans(opts = {}, &block)
    raise "EventMachine not initialized" unless @em_monitor
    @em_monitor.monitor_spans(opts[:interval] || Monitor::DEFAULT_INTERVAL, &block)
  end

  # Set the block to be called periodically with histogram data.
  #
  # This is a convenience wrapper around {monitor_spans} for the common use-case of
  # wanting to plot a histogram of loop utilisation split into time-chunks.
  #
  # In the normal case you can plot these values directly and it will tell you
  # how much CPU-time was used by spans shorter than a given length. However, care
  # should be taken if CPU-spans are often of similar length to :interval. This can
  # cause the actual delay between calls to the block to vary significantly and so
  # if you're trying to plot a line of CPU-utilization then it can give you misleading
  # answers. If this is a concern to you then you might want to use the :cumulative
  # mode and ask your graphing library to plot the derivative of the values over time.
  #
  # @param [Hash] opts  Configuration for the histogram
  # @param [Proc] block  the block to call.
  #
  # @option opts [Number] :interval (60)
  #   The approximate number of seconds between calls to your block.
  #   If your event loop regularly runs long CPU-spans then the actual time between
  #   calls can vary significantly.
  #
  # @option opts [Array<Number>] :buckets ([0.001, 0.01, 0.1, 1, 10, Infinity])
  #   The boundaries of the histogram buckets, Infinity will be added even if it's not
  #   specified by you to ensure that all spans are included.
  #   CPU-spans are put into the smallest bucket with a limit longer than the span.
  #
  # @option opts [Boolean] :stacked (false)
  #   When true larger buckets include the sum of all smaller buckets in addition to
  #   the number of seconds spent in CPU-spans that fell into that bucket directly.
  #   When false each CPU-span will be put into exactly one bucket
  #
  # @option opts [Boolean] :cumulative (false)
  #   When true the values of each bucket will increase monotonically over the
  #   lifetime of the process and the derivative over time can be used to tell
  #   how much CPU was used by spans in each bucket in the current monitoring
  #   interval.
  #   When false the values of each bucket are only the amount of time spent
  #   by CPU-spans in that bucket in the current monitoring interval.
  #
  # @yieldparam [Hash<Float,Float>] histogram  A histogram from bucket-size to
  #   amount of CPU-time spent in that bucket.
  # @yieldparam [Time] from  The start of the monitoring interval
  # @yieldparam [Time] to    The end of the monitoring interval
  #
  # @example
  #   # Create an input file suitable for feeding to gnuplot.
  #   #
  #   EM::monitor_histogram(stacked: true) do |hist, from, to|
  #     gnuplot_input.puts #{to.iso8601} #{hist.values.join(" ")}"
  #   end
  def self.monitor_histogram(opts = {}, &block)
    stacked    = !!opts[:stacked]
    cumulative = !!opts[:cumulative]
    interval   =   opts[:interval] || Monitor::DEFAULT_INTERVAL
    buckets    =  (opts[:buckets]  || Monitor::DEFAULT_BUCKETS).sort
    buckets << (1/0.0)

    # create the histogram keys in (sorted) bucket order to ensure
    # that histogram.values.join(" ") always does the right thing
    hist = buckets.each_with_object({}){ |bucket, h| h[bucket] = 0 }

    monitor_spans(opts) do |spans, from, to|

      unless cumulative
        hist = buckets.each_with_object({}){ |bucket, h| h[bucket] = 0 }
      end

      if stacked
        spans.each do |span|
          buckets.each do |bucket|
            hist[bucket] += span if bucket > span
          end
        end
      else
        spans.each do |span|
          hist[buckets.detect{ |bucket| bucket > span }] += span
        end
      end

      block.call hist, from, to
    end
  end

  # The monitor object itself deals with maintaining lspace and
  # timers.
  class Monitor
    # How long (by default) between calls to monitors
    DEFAULT_INTERVAL = 60
    # Which buckets to include in the histogram by default
    DEFAULT_BUCKETS = [0.001, 0.01, 0.1, 1, 10]

    # Create a new monitor.
    #
    # The block will be called in the monitor's LSpace, all further
    # EM work should happen within the block to ensure that we measure
    # everything.
    #
    # @param [Proc] block  The block during which to monitor events
    # @yieldparam [Monitor] self
    def initialize(&block)
      create_lspace.enter do
        block.call self
      end
    end

    # Attach a listener to this monitor.
    #
    # Only one listener can be active at a time, and the interval set
    # here will take affect after the next tick of the previous interval.
    #
    # @param [Number] interval  The (lower bound of) time in seconds between calls to block
    # @param [Proc] block  The block to call
    # @yieldparam [Array<Float>] spans  Each number of seconds the event loop spent processing.
    # @yieldparam [Time] from  The time at which the block was previously called
    # @yieldparam [Time] to  The current time
    # @see EM.monitor_spans
    def monitor_spans(interval, &block)
      @periodic_timer ||= create_timer(interval)
      @periodic_timer.interval = interval
      @monitor = block
    end

    private

    # Add an around_filter to LSpace that wraps every CPU-span in a timing function.
    #
    # @return [LSpace]
    def create_lspace
      LSpace.new.around_filter do |&block|
        start = Time.now
        begin
          block.call
        ensure
          @timings << Time.now - start if @timings
        end
      end
    end

    # Add a periodic timer that will periodically call @monitor with the contents
    # of @timings.
    #
    # @param [Number] interval  The interval to use for the timer.
    # @return [EM::PeriodicTimer]
    def create_timer(interval)
      @timings = []
      time = Time.now
      EM::PeriodicTimer.new(interval) do
        # Set last_time to *before* we call the monitor.
        # This is because the duration of the monitor will be included in the next set of
        # timings.
        last_time, time = time, Time.now
        timings = @timings.slice!(0..-1)
        @monitor.call timings, last_time, time
      end
    end
  end
end
