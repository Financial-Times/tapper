defmodule Tracer.TimeoutTest do

  use ExUnit.Case

  alias Tapper.Tracer.Timeout
  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  import Test.Helper.Server

  describe "child_spans/1" do

    test "when only main span returns []" do

      trace = %Trace{
        span_id: 0x1,
        spans: %{
          1 => %Trace.SpanInfo{id: 1}
        }
      }

      assert Timeout.child_spans(trace) == []
    end

    test "when child spans exist returns Enumerable of child spans" do

      trace = %Trace{
        span_id: 1,
        spans: %{
          1 => %Trace.SpanInfo{id: 1},
          2 => %Trace.SpanInfo{id: 2},
        }
      }

      child_spans = Timeout.child_spans(trace)

      assert child_spans != []
      refute trace.spans[1] in Enum.to_list(child_spans)
      assert trace.spans[2] in Enum.to_list(child_spans)
    end
  end

  test "span_finished?/1" do
    refute Timeout.span_finished?(%Trace.SpanInfo{end_timestamp: nil})
    assert Timeout.span_finished?(%Trace.SpanInfo{end_timestamp: 1})
  end

  describe "all_finished/1" do

    test "returns true when all finished" do
      spans = [%Trace.SpanInfo{end_timestamp: 1},%Trace.SpanInfo{end_timestamp: 2}]
      assert Timeout.all_finished?(spans)
    end

    test "returns false when one unfinished" do
      spans = [%Trace.SpanInfo{end_timestamp: 1},%Trace.SpanInfo{end_timestamp: nil}]
      refute Timeout.all_finished?(spans)
    end

    test "returns true when no spans" do
      assert Timeout.all_finished?([])
    end
  end

  describe "latest_timeout/1" do

    test "returns false when there are no completed spans" do
      spans = [%Trace.SpanInfo{end_timestamp: nil}, %Trace.SpanInfo{end_timestamp: nil}]
      refute Timeout.latest_timeout(spans)
    end

    test "returns false when there are no spans" do
      refute Timeout.latest_timeout([])
    end

    test "returns expected max end_timestamp when spans completed" do
      timestamp_1 = Timestamp.instant()
      timestamp_2 = Timestamp.incr(timestamp_1, 9)
      timestamp_3 = Timestamp.incr(timestamp_1, 7)

      spans = [
        %Trace.SpanInfo{end_timestamp: timestamp_1},
        %Trace.SpanInfo{end_timestamp: timestamp_2},
        %Trace.SpanInfo{end_timestamp: timestamp_3}
      ]

      assert Timeout.latest_timeout(spans) === timestamp_2
    end
  end

  describe "annotate_timeout_spans/3" do

    test "does nothing if all spans completed" do
      timestamp_1 = Timestamp.instant()
      timestamp_2 = Timestamp.incr(timestamp_1, 2)

      endpoint = random_endpoint()
      spans = %{
        1 => %Trace.SpanInfo{end_timestamp: timestamp_1},
        2 => %Trace.SpanInfo{end_timestamp: timestamp_2}
      }

      timeout_timestamp = Timestamp.incr(timestamp_1, 99)

      result = Timeout.annotate_timeout_spans(spans, timeout_timestamp, endpoint)

      assert result === spans
    end

    test "places sets end_timestamp on incomplete spans" do
      endpoint = random_endpoint()

      timestamp = Timestamp.instant()
      timestamp_1 = Timestamp.incr(timestamp, 100)
      timestamp_3 = Timestamp.incr(timestamp, 300)

      spans = %{
        1 => %Trace.SpanInfo{end_timestamp: timestamp_1},
        2 => %Trace.SpanInfo{},
        3 => %Trace.SpanInfo{end_timestamp: timestamp_3},
      }

      timeout_timestamp = Timestamp.incr(timestamp, 1000)
      result = Timeout.annotate_timeout_spans(spans, timeout_timestamp, endpoint)

      refute result === spans

      assert result[1].end_timestamp === timestamp_1
      assert result[2].end_timestamp === timeout_timestamp
      assert result[3].end_timestamp === timestamp_3
    end

    test "places timeout annotations on incomplete spans" do
      endpoint = random_endpoint()

      timestamp = Timestamp.instant()
      timestamp_1 = Timestamp.incr(timestamp, 1)
      timestamp_3 = Timestamp.incr(timestamp, 3)
      timestamp_existing = Timestamp.incr(timestamp, 10)

      existing_annotation = Trace.Annotation.new(:xx, timestamp_existing, endpoint)

      spans = %{
        1 => %Trace.SpanInfo{end_timestamp: timestamp_1, annotations: [existing_annotation]},
        2 => %Trace.SpanInfo{annotations: []},
        3 => %Trace.SpanInfo{end_timestamp: timestamp_3, annotations: []},
        4 => %Trace.SpanInfo{annotations: [existing_annotation]}
      }

      timeout_timestamp = Timestamp.incr(timestamp, 100)

      result = Timeout.annotate_timeout_spans(spans, timeout_timestamp, endpoint)

      assert result[1].annotations == spans[1].annotations

      assert [Timeout.timeout_annotation(timeout_timestamp, endpoint)] == result[2].annotations

      assert result[3].annotations == spans[3].annotations

      assert Timeout.timeout_annotation(timeout_timestamp, endpoint) in result[4].annotations
      assert existing_annotation in result[4].annotations
      assert length(result[4].annotations) === 2
    end

  end

  describe "timeout_trace/2 non-async" do

    test "sets end_timestamp and annotates main and unfinished spans with timeout" do
      timestamp = Timestamp.instant()

      trace = %Trace{
        span_id: 1,
        spans: %{
          1 => %Trace.SpanInfo{id: 1, annotations: []},
          2 => %Trace.SpanInfo{id: 2, end_timestamp: timestamp, annotations: []},
          3 => %Trace.SpanInfo{id: 3, annotations: []}
        },
        config: config(),
        last_activity: Timestamp.incr(timestamp, 3000)
      }

      timeout_timestamp = Timestamp.incr(timestamp, 10_000)

      result = Timeout.timeout_trace(trace, timeout_timestamp)

      assert result.end_timestamp == timeout_timestamp

      assert result.spans[1].end_timestamp == timeout_timestamp
      assert result.spans[2].end_timestamp == trace.spans[2].end_timestamp
      assert result.spans[3].end_timestamp == timeout_timestamp

      assert length(result.spans[1].annotations) === 1
      assert length(result.spans[2].annotations) === 0
      assert length(result.spans[3].annotations) === 1

      assert hd(result.spans[1].annotations).value == :timeout
      assert hd(result.spans[3].annotations).value == :timeout
    end

  end

  describe "timeout_trace/2 async" do

    test "sets end_timestamp and annotates main and unfinished spans with :timeout when unfinished spans" do
      timestamp = Timestamp.instant()

      trace = %Trace{
        span_id: 1,
        async: true,
        spans: %{
          1 => %Trace.SpanInfo{id: 1, annotations: []}, # NB unfinished main span, async so OK
          2 => %Trace.SpanInfo{id: 2, end_timestamp: timestamp, annotations: []},
          3 => %Trace.SpanInfo{id: 3, annotations: []}
        },
        config: config(),
        last_activity: Timestamp.incr(timestamp, 3000)
      }

      timeout_timestamp = Timestamp.incr(timestamp, 10_000)

      result = Timeout.timeout_trace(trace, timeout_timestamp)

      assert result.end_timestamp == timeout_timestamp

      assert result.spans[1].end_timestamp == timeout_timestamp
      assert result.spans[2].end_timestamp == trace.spans[2].end_timestamp
      assert result.spans[3].end_timestamp == timeout_timestamp

      assert length(result.spans[1].annotations) === 1
      assert length(result.spans[2].annotations) === 0
      assert length(result.spans[3].annotations) === 1

      assert hd(result.spans[1].annotations).value == :timeout
      assert hd(result.spans[3].annotations).value == :timeout
    end

    test "sets main span end_timestamp as latest span end_timestamp when no unfinished spans" do
      timestamp = Timestamp.instant()

      timestamp_2 = Timestamp.incr(timestamp, 2000)
      timestamp_3 = Timestamp.incr(timestamp, 1000)

      trace = %Trace{
        span_id: 1,
        async: true,
        spans: %{
          1 => %Trace.SpanInfo{id: 1, annotations: []}, # NB unfinished main span, async so OK
          2 => %Trace.SpanInfo{id: 2, end_timestamp: timestamp_2, annotations: []},
          3 => %Trace.SpanInfo{id: 3, end_timestamp: timestamp_3, annotations: []}
        },
        config: config(),
        last_activity: Timestamp.incr(timestamp, 3000)
      }

      timeout_timestamp = Timestamp.incr(timestamp, 10_000)

      result = Timeout.timeout_trace(trace, timeout_timestamp)

      assert result.end_timestamp === trace.spans[2].end_timestamp, "Expected trace to gain span 2 end_timestamp"

      assert result.spans[1].end_timestamp === trace.spans[2].end_timestamp, "Expected main span to gain span 2 end_timestamp"
      assert result.spans[2].end_timestamp === trace.spans[2].end_timestamp
      assert result.spans[3].end_timestamp === trace.spans[3].end_timestamp

      assert result.spans[1].annotations == trace.spans[1].annotations
      assert result.spans[1].annotations == trace.spans[2].annotations
      assert result.spans[3].annotations == trace.spans[3].annotations
    end

    test "sets main span end_timestamp as last_activity time when no child spans" do
      timestamp = Timestamp.instant()

      trace = %Trace{
        span_id: 1,
        async: true,
        spans: %{
          1 => %Trace.SpanInfo{id: 1, annotations: []}
        },
        config: config(),
        last_activity: Timestamp.incr(timestamp, 3000)
      }

      timeout_timestamp = Timestamp.incr(timestamp, 10_000)

      result = Timeout.timeout_trace(trace, timeout_timestamp)

      assert result.end_timestamp === trace.last_activity
      assert result.spans[1].end_timestamp === trace.last_activity
      assert result.spans[1].annotations === trace.spans[1].annotations
    end

  end
end