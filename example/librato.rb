# -*- coding: utf-8
require 'em-monitor'
require 'librato/metrics'
require 'time'

unless ENV['LIBRATO_USERNAME'] && ENV['LIBRATO_TOKEN']
  puts "Please export LIBRATO_USERNAME= and LIBRATO_TOKEN="
  exit 1
end

puts "You can watch the graph being drawn at https://metrics.librato.com/metrics/cpu-breakdown"

Librato::Metrics.authenticate ENV['LIBRATO_USERNAME'], ENV['LIBRATO_TOKEN']

EM::run do

  # Every second, upload the % of time spent in CPU-spans of various lengths to
  # librato.
  # We hack the source property to let us use the builtin stacking function.
  EM::monitor_histogram(interval: 1) do |hist, from, to|

    queue = Librato::Metrics::Queue.new

    hist.each do |k, v|
      queue.add "cpu-breakdown" => {:type => :counter, :value => (v * 100000).to_i, :source => "spans-#{k}",
                                      :display_name => "EM CPU utilization by span-length",
                                      :description => "The total of CPU-time used by spans of length X or shorter.",
                                      :attributes => {:display_units_long => 'microseconds', :display_units_short => 'μs'}
                                      }
      print "#{k}: #{v}; "
    end
    puts

    queue.submit
  end

  # Generate some sample data.
  samples = [0.0005] * 100000 + [0.005] * 10000 + [0.05] * 1000 + [0.5] * 100 + [5] * 10 + [10] * 1
  EM::PeriodicTimer.new(rand * 0.02) do
    sleep samples.sample
  end
end


