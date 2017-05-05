defmodule Tracer.Server.AnnotationTest do
  use ExUnit.Case

  import Test.Helper.Server

  alias Tapper.Tracer.Trace

  test "add annotatation, no endpoint; stores default endpoint" do
    {trace, span_id} = init_with_opts()

    value = :cr
    timestamp = System.os_time(:microseconds)

    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast({:annotation, span_id, value, timestamp, nil}, trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 2
    assert is_list(span.binary_annotations)
    assert length(span.binary_annotations) == 0

    assert %Trace.Annotation{
      value: value,
      timestamp: timestamp,
      host: Tapper.Tracer.Server.endpoint_from_config(config())
    } == hd(span.annotations)

    assert timestamp == state.last_activity
  end

  test "add annotatation, bespoke endpoint; stores endpoint" do
    {trace, span_id} = init_with_opts()

    value = :cr
    timestamp = System.os_time(:microseconds)
    endpoint = random_endpoint()

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast({:annotation, span_id, value, timestamp, endpoint}, trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 2
    assert is_list(span.binary_annotations)
    assert length(span.binary_annotations) == 0

    assert %Trace.Annotation{
      value: value,
      timestamp: timestamp,
      host: endpoint
    } == hd(span.annotations)

    assert timestamp == state.last_activity
  end

  test "add two annotatations preserves existing annotations" do
    {trace, span_id} = init_with_opts()

    value_1 = :cr
    timestamp_1 = System.os_time(:microseconds)
    endpoint_1 = random_endpoint()

    {:noreply, state_1, _ttl} =
      Tapper.Tracer.Server.handle_cast({:annotation, span_id, value_1, timestamp_1, endpoint_1}, trace)

    value_2 = :my_custom_annotation
    timestamp_2 = timestamp_1 + 1
    endpoint_2 = random_endpoint()

    {:noreply, state_2, _ttl} =
      Tapper.Tracer.Server.handle_cast({:annotation, span_id, value_2, timestamp_2, endpoint_2}, state_1)

    span = state_2.spans[span_id]

    assert is_list(span.binary_annotations)
    assert length(span.binary_annotations) == 0

    [annotation_2, annotation_1, _] = span.annotations

    assert %Trace.Annotation{
      value: value_1,
      timestamp: timestamp_1,
      host: endpoint_1
    } == annotation_1

    assert %Trace.Annotation{
      value: value_2,
      timestamp: timestamp_2,
      host: endpoint_2
    } == annotation_2

    assert timestamp_2 == state_2.last_activity
  end

  test "add annotatation, no matching span, does nothing (supervisor restart case)" do
    {trace, _span_id} = init_with_opts()

    value = :cr
    timestamp = System.os_time(:microseconds)

    no_span_id = Tapper.SpanId.generate()
    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast({:annotation, no_span_id, value, timestamp, nil}, trace)

    assert state.spans == trace.spans
    assert timestamp == state.last_activity
  end

  test "add binary annotation, no endpoint" do
    {trace, span_id} = init_with_opts()

    type = :string
    key = "http_method"
    value = "POST"
    timestamp = System.os_time(:microseconds)

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast({:binary_annotation, span_id, type, key, value, timestamp, nil}, trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 1

    assert is_list(span.binary_annotations)
    assert length(span.binary_annotations) == 1

    assert %Trace.BinaryAnnotation{
      annotation_type: type,
      key: key,
      value: value,
      host: Tapper.Tracer.Server.endpoint_from_config(config())
    } == hd(span.binary_annotations)

    assert timestamp == state.last_activity
  end

  test "add binary annotation, bespoke endpoint" do
    {trace, span_id} = init_with_opts()

    type = :string
    key = "http_method"
    value = "POST"
    timestamp = System.os_time(:microseconds)
    endpoint = random_endpoint()

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast({:binary_annotation, span_id, type, key, value, timestamp, endpoint}, trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 1

    assert is_list(span.binary_annotations)
    assert length(span.binary_annotations) == 1

    assert %Trace.BinaryAnnotation{
      annotation_type: type,
      key: key,
      value: value,
      host: endpoint
    } == hd(span.binary_annotations)

    assert timestamp == state.last_activity
  end

  test "add two binary annotatations preserves existing annotations" do
    {trace, span_id} = init_with_opts()

    type_1 = :string
    key_1 = "http_method"
    value_1 = "GET"
    timestamp_1 = System.os_time(:microseconds)
    endpoint_1 = random_endpoint()

    {:noreply, state_1, _ttl} =
      Tapper.Tracer.Server.handle_cast({:binary_annotation, span_id, type_1, key_1, value_1, timestamp_1, endpoint_1}, trace)

    type_2 = :i16
    key_2 = "http_status"
    value_2 = 404
    timestamp_2 = System.os_time(:microseconds)
    endpoint_2 = random_endpoint()

    {:noreply, state_2, _ttl} =
      Tapper.Tracer.Server.handle_cast({:binary_annotation, span_id, type_2, key_2, value_2, timestamp_2, endpoint_2}, state_1)


    span = state_2.spans[span_id]

    assert length(span.annotations) == 1

    [annotation_2, annotation_1] = span.binary_annotations

    assert %Trace.BinaryAnnotation{
      annotation_type: type_1,
      key: key_1,
      value: value_1,
      host: endpoint_1
    } == annotation_1

    assert %Trace.BinaryAnnotation{
      annotation_type: type_2,
      key: key_2,
      value: value_2,
      host: endpoint_2
    } == annotation_2

    assert timestamp_2 == state_2.last_activity
  end

  test "add binary annotation, no matching span, does nothing (supervisor restart case)" do
    {trace, _span_id} = init_with_opts()

    type = :string
    key = "http_method"
    value = "POST"
    timestamp = System.os_time(:microseconds)

    no_span_id = Tapper.SpanId.generate()
    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast({:binary_annotation, no_span_id, type, key, value, timestamp, nil}, trace)

    assert state.spans == trace.spans
    assert timestamp == state.last_activity
  end

  test "annotate timeout spans" do
    endpoint = random_endpoint()
    timestamp = :rand.uniform(2000)

    spans = %{
      "1" => %Trace.SpanInfo{
        start_timestamp: timestamp,
        end_timestamp: timestamp + 100,
        annotations: []
      },
      "2" => %Trace.SpanInfo{
        start_timestamp: timestamp + 200,
        annotations: []
      },
      "3" => %Trace.SpanInfo{
        start_timestamp: timestamp + 400,
        annotations: [
          %Trace.Annotation{
            value: :cr,
            timestamp: timestamp + 410,
            host: endpoint
          }
        ]
      }
    }

    timestamp = timestamp + 500
    expected_annotation = %Trace.Annotation{value: :timeout, timestamp: timestamp, host: endpoint}


    annotated_spans = Tapper.Tracer.Server.annotate_timeout_spans(spans, timestamp, endpoint)


    assert is_map(annotated_spans)

    %{"1" => annotated_span_1 = %Trace.SpanInfo{}, "2" => annotated_span_2 = %Trace.SpanInfo{}, "3" => annotated_span_3 = %Trace.SpanInfo{}} = annotated_spans

    assert annotated_span_1 == spans["1"], "Finished span should not change"

    assert annotated_span_2.start_timestamp === spans["2"].start_timestamp
    assert annotated_span_2.end_timestamp === timestamp
    assert length(annotated_span_2.annotations) === 1
    assert expected_annotation in annotated_span_2.annotations

    assert annotated_span_3.start_timestamp === spans["3"].start_timestamp
    assert annotated_span_3.end_timestamp === timestamp
    assert length(annotated_span_3.annotations) === 2
    assert expected_annotation in annotated_span_3.annotations
    assert hd(spans["3"].annotations) in annotated_span_3.annotations
  end

end