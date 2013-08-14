em-monitor is a gem that lets you monitor your eventmachine reactor.

Introduction
============

As we all know, event loops are an awesome programming model. You can (mostly) forget
about thread-safety, but you can still do a bazillion IO-things in parallel.

They do have one significant downside though: you can only run one CPU-thing at a time.

This means that if you accidentally spend 30 seconds running a bad regex, everything in
your loop is going to get stuck for 30 seconds (that's about a million years in computer
terms). This is particularly bad because one user who triggers a bad regex slows down all
your other users for *all 30 seconds*.

EM::Monitor can't fix your code for you, but it can let you know you have a problem.

Usage
=====

em-monitor wraps every CPU-span of code in your program and measures how long is spent
executing it. You can then extract this data periodically in two ways. `EM::monitor_spans`
calls a block with an array of raw measurements on a regular interval (by default 60
seconds), `EM::monitor_histogram` buckets all the measurements and then sums them. This
lets you plot the amount of time that your event loop is spending running short CPU-spans
against the amount of time that your event loop is spending running long CPU-spans.

```ruby
EM::monitor_spans(interval: 1) do |spans, from, to|
  puts "Between #{from} and #{to} (#{to-from}seconds) there were #{spans.size} CPU-spans:"
  puts spans.inspect
end
#=> Between 2013-02-07 02:19:37 and 2013-02-07 02:19:38 (1.00 seconds) there were 7 CPU-spans:
#=> [0.000565469, 0.000564702, 0.000568218, 0.000564348, 0.005066146, 0.050109482, 0.050113617]

EM::monitor_histogram(interval: 1) do |histogram, from, to|
  puts "In the last #{to - from} real seconds, we used #{histogram.values.inject(&:+)} CPU-seconds"
  histogram.each do |key, value|
    puts "#{value} CPU-seconds in spans shorter than #{key} seconds"
  end
end
#=> In the last 1.00 real seconds, we used 0.1572 CPU-seconds
# => 0.0452 CPU-seconds in spans shorter than 0.001 seconds
# => 0.0619 CPU-seconds in spans shorter than 0.01 seconds
# => 0.0500 CPU-seconds in spans shorter than 0.1 seconds
# => 0 CPU-seconds in spans shorter than 1 seconds
# => 0 CPU-seconds in spans shorter than 10 seconds
# => 0 CPU-seconds in spans shorter than Infinity seconds
```

Plotting results
================

The easiest way to plot the histogram data is as a stacked chart. If your tool of choice
can't stack charts directly you can call `EM::monitor_histogram(stacked: true)` and this
will cause larger buckets to include the sum of all the smaller buckets in addition to the
CPU-spans that fell into that bucket directly.

This will give you a graph of absolute time used per minute, which you can normalize to a
utilization percentage in two ways:

```ruby
# The absolute magnitude of the lines plotted here will be correct,
# however if you plot a stacked area graph the area will under-estimate the impact
# of CPU-spans of similar order of magnitude to `interval`.
histogram.map{ |key, value| value * 100 / (to - from) }

# Looking at the absolute magnitude of this graph will over-estimate CPU-spans
# in the short term, however if you plot a stacked area graph the area will be
# more correct.
histogram.map{ |key, value| value * 100 / interval }
```

If you need to combine the results from multiple machines you should instead use the
`EM::monitor_histogram(cumulative: true)`, and centrally keep track of the total
cumulative CPU. Plotting the derivative after summing will give you a stable plot that
makes sense when averaged.

To get a feel for how this works look at `example/gnuplot.rb` or `example/librato.rb`.

Meta-fu
=======
There's [API documentation](http://rdoc.info/github/ConradIrwin/em-monitor/master/frames)
if you'd like it.

Everything is licensed under the MIT license, see `LICENSE.MIT` for details.

Pull requests and bug reports are very welcome.
