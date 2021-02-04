defmodule Tracer.Server.SpanTest do

  # NB these tests run outside of a GenServer, i.e. we call the server directly in a single test process,

  use ExUnit.Case

  import Test.Helper.Server
  import Test.Helper.Protocol

  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  require Logger

  test "start_span updates spans and last_activity" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = Timestamp.instant()
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    assert state.spans[child_span.id]
    assert state.spans[child_span.id].start_timestamp == timestamp
    assert state.last_activity == timestamp
  end

  test "finish_span updates spans and last_activity" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = Timestamp.instant()
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    child_end_timestamp = Timestamp.incr(timestamp, 100, :millisecond)
    {:noreply, state, _ttl} =
      Tapper.Tracer.Server.handle_cast({:finish_span, child_span.id, child_end_timestamp,
        annotations: [
          Tapper.Tracer.annotation_delta(:xx),
          Tapper.Tracer.annotation_delta("something")
        ]}, state)

    assert state.spans[child_span.id]
    assert state.spans[child_span.id].start_timestamp == timestamp
    assert state.spans[child_span.id].end_timestamp == child_end_timestamp
    assert state.last_activity == child_end_timestamp
    assert annotation_by_value(state.spans[child_span.id], :xx)
    assert annotation_by_value(state.spans[child_span.id], "something")
  end

  test "start_span with local context option adds lc annotation" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = Timestamp.instant()
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, [local: "my_function"]}, trace)

    assert state.spans[child_span.id]
    binary_annotations = state.spans[child_span.id].binary_annotations
    assert %Tapper.Tracer.Trace.BinaryAnnotation{annotation_type: :string, key: :lc, value: "my_function", host: Trace.endpoint_from_config(config())} in binary_annotations
  end

  test "start_span with local context option (as atom) adds lc annotation" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = Timestamp.instant()
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, [local: MyAtom]}, trace)

    assert state.spans[child_span.id]
    binary_annotations = state.spans[child_span.id].binary_annotations
    assert %Tapper.Tracer.Trace.BinaryAnnotation{annotation_type: :string, key: :lc, value: MyAtom, host: Trace.endpoint_from_config(config())} in binary_annotations
  end

  test "finish_span when no matching span is harmless (supervisor restart case)" do

    {trace, _span_id} = init_with_opts(config: config())

    timestamp = Timestamp.instant()
    span_id = Tapper.SpanId.generate()

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:finish_span, span_id, timestamp, []}, trace)

    assert state.spans == trace.spans
    assert state.last_activity == timestamp
  end

  test "finish (not async) reports spans" do

    {ref, reporter} = msg_reporter()
    config = put_in(config()[:reporter], reporter)

    {trace, span_id} = init_with_opts(config: config)

    timestamp = Timestamp.instant()

    {:stop, :normal, []} = Tapper.Tracer.Server.handle_cast({:finish, timestamp,
      annotations: [{:binary_annotate, {:string, :yy, "yyy", nil}}, {:annotate, {:xx, nil}}]}, trace)

    assert_received {^ref, spans}

    assert is_list(spans)
    assert length(spans) == 1

    [%Tapper.Protocol.Span{id: ^span_id, annotations: annotations, binary_annotations: binary_annotations}] = spans

    assert protocol_annotation_by_value(annotations, :cs)
    assert protocol_annotation_by_value(annotations, :xx)
    assert protocol_binary_annotation_by_key(binary_annotations, :yy)
  end

  test "finish async tags main span and timeout reports spans" do

    {ref, reporter} = msg_reporter()
    config = put_in(config()[:reporter], reporter)

    ttl = 1000

    {trace, span_id} = init_with_opts(config: config, ttl: 1000)

    # add a child span to simulate one running async
    timestamp = Timestamp.instant()

    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)
    {:noreply, state, ^ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    assert state.spans[child_span.id]

    # finish asynchronously
    timestamp = Timestamp.instant()

    {:noreply, state, ^ttl} = Tapper.Tracer.Server.handle_cast({:finish, timestamp, async: true, annotations: [Tapper.Tracer.annotation_delta(:xx)]}, state)

    span = state.spans[trace.span_id]

    assert Trace.has_annotation?(span, :xx)
    assert Trace.has_annotation?(span, :async)

    assert hd(span.annotations) == %Tapper.Tracer.Trace.Annotation{
      value: :async,
      timestamp: timestamp,
      host: Trace.endpoint_from_config(config)
    }

    refute_received {^ref, _spans}, "Async finish should not have called reporter"

    # simulate timeout (since we're not running in a GenServer)
    {:stop, :normal, _} = Tapper.Tracer.Server.handle_info(:timeout, state)

    assert_received {^ref, spans}

    assert is_list(spans)
    assert length(spans) == 2

    main_proto_span = Enum.find(spans, fn(span) -> span.id == span_id end)
    child_proto_span = Enum.find(spans, fn(span) -> span.id == child_span.id end)

    assert main_proto_span
    assert child_proto_span

    %Tapper.Protocol.Span{id: ^span_id, annotations: annotations, binary_annotations: binary_annotations} = main_proto_span

    assert protocol_annotation_by_value(annotations, :cs)
    assert protocol_annotation_by_value(annotations, :async)

    assert binary_annotations == []
  end


  def child_span_info(name, child_span_id, parent_id, timestamp) do
    %Tapper.Tracer.Trace.SpanInfo{
      name: name,
      id: child_span_id,
      parent_id: parent_id,
      start_timestamp: timestamp,
      annotations: [],
      binary_annotations: []
    }
  end

end
