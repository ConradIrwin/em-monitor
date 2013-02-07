require 'em-monitor'
require 'time'

at_exit do
  exec %(gnuplot -e 'load "example/stacked.plot"' -p)
end

puts "When you've gathered enough data (about 30s should be enough) hit <Ctrl-C>"

EM::run do
  file = File.open("/tmp/to_plot", "w")

  # Every second, output the % of time spent in CPU-spans of various lengths in a
  # gnuplot-readable format.
  EM::monitor_histogram(interval: 1, stacked: true) do |hist, from, to|
    percentages = hist.map{ |k, v| (v * 100 / (to - from)) }

    file.puts "#{Time.now.utc.iso8601} #{percentages.join(" ")}"
    file.flush
    puts "#{Time.now.utc.iso8601} #{percentages.map{ |x| "%0.2f" % x }.join(" ")}"
  end

  # Generate some sample data.
  samples = [0.0005] * 100000 + [0.005] * 10000 + [0.05] * 1000 + [0.5] * 100 + [5] * 10 + [10] * 1
  EM::PeriodicTimer.new(rand * 0.02) do
    sleep samples.sample
  end
end

