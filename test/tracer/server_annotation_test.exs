defmodule Tracer.Server.AnnotationTest do
  use ExUnit.Case

  import Test.Helper.Server

  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  test "add annotatation, no endpoint; stores default endpoint" do
    {trace, span_id} = init_with_opts()

    value = :cr
    timestamp = Timestamp.instant()

    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast(annotation_update_message(span_id, timestamp, {value, nil}), trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 2
    assert is_list(span.binary_annotations)
    assert span.binary_annotations == []

    assert %Trace.Annotation{
      value: value,
      timestamp: timestamp,
      host: Trace.endpoint_from_config(config())
    } == hd(span.annotations)

    assert timestamp == state.last_activity
  end

  test "add short annotatation" do
    {trace, span_id} = init_with_opts()

    timestamp = Timestamp.instant()
    value = :ss

    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast(annotation_update_message(span_id, timestamp, :ss), trace)

    span = state.spans[span_id]

    assert %Trace.Annotation{
      value: value,
      timestamp: timestamp,
      host: Trace.endpoint_from_config(config())
    } == hd(span.annotations)
  end

  test "handles a single annotatation rather than a list of annotations" do
    {trace, span_id} = init_with_opts()

    timestamp = Timestamp.instant()
    value = :ss

    msg = {:update, span_id, timestamp, Tapper.Tracer.annotation_delta(value, nil)}
    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast(msg, trace)

    span = state.spans[span_id]

    assert %Trace.Annotation{
      value: value,
      timestamp: timestamp,
      host: Trace.endpoint_from_config(config())
    } == hd(span.annotations)
  end

  test "add annotatation, bespoke endpoint; stores endpoint" do
    {trace, span_id} = init_with_opts()

    value = :cr
    timestamp = Timestamp.instant()
    endpoint = random_endpoint()

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast(annotation_update_message(span_id, timestamp, {value, endpoint}), trace)

    assert is_map(state.spans)

    span = state.spans[span_id]
    assert span

    assert is_list(span.annotations)
    assert length(span.annotations) == 2
    assert is_list(span.binary_annotations)
    assert span.binary_annotations == []

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
    timestamp_1 = {instant, offset} = Timestamp.instant()
    endpoint_1 = random_endpoint()

    {:noreply, state_1, _ttl} =
      Tapper.Tracer.Server.handle_cast(annotation_update_message(span_id, timestamp_1, {value_1, endpoint_1}), trace)

    value_2 = :my_custom_annotation
    timestamp_2 = {instant + 1, offset}
    endpoint_2 = random_endpoint()

    {:noreply, state_2, _ttl} =
      Tapper.Tracer.Server.handle_cast(annotation_update_message(span_id, timestamp_2, {value_2, endpoint_2}), state_1)

    span = state_2.spans[span_id]

    assert is_list(span.binary_annotations)
    assert span.binary_annotations == []

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
    timestamp = Timestamp.instant()

    no_span_id = Tapper.SpanId.generate()
    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast(annotation_update_message(no_span_id, timestamp, {value, nil}), trace)

    assert state.spans == trace.spans
    assert timestamp == state.last_activity
  end

  test "add binary annotation, no endpoint" do
    {trace, span_id} = init_with_opts()

    type = :string
    key = "http_method"
    value = "POST"
    timestamp = Timestamp.instant()

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast(binary_annotation_update_message(span_id, timestamp, {type, key, value, nil}), trace)

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
      host: Trace.endpoint_from_config(config())
    } == hd(span.binary_annotations)

    assert timestamp == state.last_activity
  end

  test "add binary annotation, bespoke endpoint" do
    {trace, span_id} = init_with_opts()

    type = :string
    key = "http_method"
    value = "POST"
    timestamp = Timestamp.instant()
    endpoint = random_endpoint()

    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast(binary_annotation_update_message(span_id, timestamp, {type, key, value, endpoint}), trace)

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
    timestamp_1 = Timestamp.instant()
    endpoint_1 = random_endpoint()

    {:noreply, state_1, _ttl} =
      Tapper.Tracer.Server.handle_cast(binary_annotation_update_message(span_id, timestamp_1, {type_1, key_1, value_1, endpoint_1}), trace)

    type_2 = :i16
    key_2 = "http_status"
    value_2 = 404
    timestamp_2 = Timestamp.instant()
    endpoint_2 = random_endpoint()

    {:noreply, state_2, _ttl} =
      Tapper.Tracer.Server.handle_cast(binary_annotation_update_message(span_id, timestamp_2, {type_2, key_2, value_2, endpoint_2}), state_1)


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
    timestamp = Timestamp.instant()

    no_span_id = Tapper.SpanId.generate()
    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast(binary_annotation_update_message(no_span_id, timestamp, {type, key, value, nil}), trace)

    assert state.spans == trace.spans
    assert timestamp == state.last_activity
  end

end
