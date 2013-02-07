$: << './lib'
require 'em-monitor'
require 'minitest/autorun'
require 'pry'

class TestEmMonitor < MiniTest::Unit::TestCase

  def test_before_running
    e = assert_raises(RuntimeError){ EM::monitor_spans }
    assert_equal "EventMachine not initialized", e.message
  end

  def test_monitor_spans
    spans = from = to = nil

    EM::run do
      EM::monitor_spans(interval: 0.1) do |*a|
        spans, from, to = a
        EM::stop
      end
      10.times do
        EM::next_tick{ sleep 0.005 }
      end
      sleep 0.05
    end

    assert_equal spans.size, 11
    assert_in_delta spans.first, 0.05

    spans.drop(1).each do |span|
      assert_in_delta span, 0.005
    end

    assert_in_delta(to - from, 0.1, 0.002)
  end

  def test_span_raising_exception
    spans = from = to = nil
    EM::run do
      EM::monitor_spans(interval: 0.1) do |*a|
        spans, from, to = a
        EM::stop
      end
      EM::error_handler do
        sleep 0.006
      end

      EM::next_tick do
        sleep 0.004
        raise "oops"
      end

      sleep 0.002
    end

    assert_in_delta spans[0], 0.002
    assert_in_delta spans[1], 0.004
    assert_in_delta spans[2], 0.006
  end

  def test_monitor_histograms
    histogram = from = to = nil

    EM::run do
      EM::monitor_histogram(interval: 0.6,  buckets: [0.01, 0.02, 0.03, 0.04]) do |*a|
        histogram, from, to = a
        EM::stop
      end
      4.times do |i|
        EM::next_tick{
          5.times do
            EM::next_tick{ sleep(0.005 + i * 0.01) }
          end
        }
      end
      sleep 0.055
    end

    assert_equal histogram.keys, [0.01, 0.02, 0.03, 0.04, 1/0.0]

    assert_in_delta histogram[0.01], 0.025
    assert_in_delta histogram[0.02], 0.075
    assert_in_delta histogram[0.03], 0.125
    assert_in_delta histogram[0.04], 0.175
    assert_in_delta histogram[1 / 0.0], 0.055
    assert_in_delta(to - from, 0.6, 0.002)
  end

  def test_stacked_histogram
    histogram = from = to = nil

    EM::run do
      EM::monitor_histogram(interval: 0.5,  buckets: [0.01, 0.02, 0.03, 0.04], stacked: true) do |*a|
        histogram, from, to = a
        EM::stop
      end
      4.times do |i|
        EM::next_tick{
          5.times do
            EM::next_tick{ sleep(0.005 + i * 0.01) }
          end
        }
      end
      sleep 0.055
    end

    assert_equal histogram.keys, [0.01, 0.02, 0.03, 0.04, 1/0.0]

    assert_in_delta histogram[0.01], 0.025, 0.01
    assert_in_delta histogram[0.02], 0.100, 0.01
    assert_in_delta histogram[0.03], 0.225, 0.01
    assert_in_delta histogram[0.04], 0.400, 0.01
    assert_in_delta histogram[1 / 0.0], 0.455, 0.01
    assert_in_delta(to - from, 0.5, 0.02)
  end

  def test_cumulative_histogram
    histogram = from = to = nil
    histogram2 = from2 = to2 = nil
    second_time = false

    EM::run do
      trigger = lambda do
        4.times do |i|
          EM::next_tick{
            5.times do
              EM::next_tick{ sleep(0.005 + i * 0.01) }
            end
          }
        end
      end
      EM::monitor_histogram(interval: 0.5,  buckets: [0.01, 0.02, 0.03, 0.04], cumulative: true) do |*a|
        if second_time
          histogram2, from2, to2 = a
          EM::stop
        else
          histogram, from, to = a
          histogram = histogram.dup
          second_time = true
          trigger.()
          sleep 0.066
        end
      end
      trigger.()
      sleep 0.055
    end

    assert_equal histogram.keys, [0.01, 0.02, 0.03, 0.04, 1/0.0]

    assert_in_delta histogram[0.01], 0.025, 0.01
    assert_in_delta histogram[0.02], 0.075, 0.01
    assert_in_delta histogram[0.03], 0.125, 0.01
    assert_in_delta histogram[0.04], 0.175, 0.01
    assert_in_delta histogram[1 / 0.0], 0.055, 0.01
    assert_in_delta(to - from, 0.5, 0.02)

    assert_equal to, from2

    assert_in_delta histogram2[0.01], 0.025 * 2, 0.01
    assert_in_delta histogram2[0.02], 0.075 * 2, 0.01
    assert_in_delta histogram2[0.03], 0.125 * 2, 0.01
    assert_in_delta histogram2[0.04], 0.175 * 2, 0.01
    assert_in_delta histogram2[1 / 0.0], 0.055 + 0.066, 0.01
    assert_in_delta(to2 - from2, 0.566, 0.01)
  end

  def test_cumulative_stacked_histogram
    histogram = from = to = nil
    histogram2 = from2 = to2 = nil
    second_time = false

    EM::run do
      trigger = lambda do
        4.times do |i|
          EM::next_tick{
            5.times do
              EM::next_tick{ sleep(0.005 + i * 0.01) }
            end
          }
        end
      end
      EM::monitor_histogram(interval: 0.5,  buckets: [0.01, 0.02, 0.03, 0.04], cumulative: true, stacked: true) do |*a|
        if second_time
          histogram2, from2, to2 = a
          EM::stop
        else
          histogram, from, to = a
          histogram = histogram.dup
          second_time = true
          trigger.()
          sleep 0.066
        end
      end
      trigger.()
      sleep 0.055
    end

    assert_equal histogram.keys, [0.01, 0.02, 0.03, 0.04, 1/0.0]

    assert_in_delta histogram[0.01], 0.025, 0.01
    assert_in_delta histogram[0.02], 0.100, 0.01
    assert_in_delta histogram[0.03], 0.225, 0.01
    assert_in_delta histogram[0.04], 0.400, 0.01
    assert_in_delta histogram[1 / 0.0], 0.455, 0.01
    assert_in_delta(to - from, 0.5, 0.02)

    assert_equal to, from2

    assert_in_delta histogram2[0.01], 0.025 * 2, 0.01
    assert_in_delta histogram2[0.02], 0.100 * 2, 0.01
    assert_in_delta histogram2[0.03], 0.225 * 2, 0.01
    assert_in_delta histogram2[0.04], 0.400 * 2, 0.01
    assert_in_delta histogram2[1 / 0.0], 0.455 + 0.466, 0.01
    assert_in_delta(to2 - from2, 0.566, 0.01)
  end

  def test_span_longer_than_interval
    spans = from = to = nil

    EM::run do
      EM::monitor_spans(interval: 0.001) do |*a|
        spans, from, to = a
        EM::stop
      end
      EM::next_tick{ sleep 0.005 }
    end

    assert_equal spans.size, 2
    assert_in_delta(spans.last, 0.005)
    assert_in_delta(to - from, 0.005, 0.002)
  end
end
