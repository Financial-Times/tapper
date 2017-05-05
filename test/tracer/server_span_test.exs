defmodule Tracer.Server.SpanTest do

  # NB these tests run outside of a GenServer, i.e. we call the server directly in a single test process,

  use ExUnit.Case

  import Test.Helper.Server

  require Logger

  test "start_span updates spans and last_activity" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = System.os_time(:microseconds)
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    assert state.spans[child_span.id]
    assert state.spans[child_span.id].start_timestamp == timestamp
    assert state.last_activity == timestamp
  end

  test "finish_span updates spans and last_activity" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = System.os_time(:microseconds)
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    child_end_timestamp = timestamp + 100
    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:finish_span, child_span.id, child_end_timestamp}, state)

    assert state.spans[child_span.id]
    assert state.spans[child_span.id].start_timestamp == timestamp
    assert state.spans[child_span.id].end_timestamp == child_end_timestamp
    assert state.last_activity == child_end_timestamp
  end

  test "start_span with local context option adds lc annotation" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = System.os_time(:microseconds)
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, [local: "my_function"]}, trace)

    assert state.spans[child_span.id]
    binary_annotations = state.spans[child_span.id].binary_annotations
    assert %Tapper.Tracer.Trace.BinaryAnnotation{annotation_type: :string, key: :lc, value: "my_function", host: Tapper.Tracer.Server.endpoint_from_config(config())} in binary_annotations
  end

  test "start_span with local context option (as atom) adds lc annotation" do

    {trace, span_id} = init_with_opts(config: config())

    timestamp = System.os_time(:microseconds)
    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, [local: MyAtom]}, trace)

    assert state.spans[child_span.id]
    binary_annotations = state.spans[child_span.id].binary_annotations
    assert %Tapper.Tracer.Trace.BinaryAnnotation{annotation_type: :string, key: :lc, value: MyAtom, host: Tapper.Tracer.Server.endpoint_from_config(config())} in binary_annotations
  end

  test "finish_span when no matching span is harmless (supervisor restart case)" do

    {trace, _span_id} = init_with_opts(config: config())

    timestamp = System.os_time(:microseconds)
    span_id = Tapper.SpanId.generate()

    {:noreply, state, _ttl} = Tapper.Tracer.Server.handle_cast({:finish_span, span_id, timestamp}, trace)

    assert state.spans == trace.spans
    assert state.last_activity == timestamp
  end

  test "finish (not async) reports spans" do

    {ref, reporter} = msg_reporter()
    config = put_in(config()[:reporter], reporter)

    {trace, span_id} = init_with_opts(config: config)

    timestamp = System.os_time(:microseconds)

    {:stop, :normal, []} = Tapper.Tracer.Server.handle_cast({:finish, timestamp, []}, trace)

    assert_received {^ref, spans}

    assert is_list(spans)
    assert length(spans) == 1

    [%Tapper.Protocol.Span{id: ^span_id, annotations: annotations, binary_annotations: binary_annotations}] = spans

    assert [%Tapper.Protocol.Annotation{value: :cs}] = annotations
    assert binary_annotations == []
  end

  test "finish async tags main span and timeout reports spans" do

    {ref, reporter} = msg_reporter()
    config = put_in(config()[:reporter], reporter)

    ttl = 1000

    {trace, span_id} = init_with_opts(config: config, ttl: 1000)

    # add a child span to simulate one running async
    timestamp = System.os_time(:microseconds)

    child_span = child_span_info("child", Tapper.SpanId.generate(), span_id, timestamp)
    {:noreply, state, ^ttl} = Tapper.Tracer.Server.handle_cast({:start_span, child_span, []}, trace)

    assert state.spans[child_span.id]

    # finish asynchronously
    timestamp = System.os_time(:microseconds)

    {:noreply, state, ^ttl} = Tapper.Tracer.Server.handle_cast({:finish, timestamp, [async: true]}, state)

    annotations = state.spans[trace.span_id].annotations

    assert is_list(annotations)
    assert length(annotations) == 2

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
      value: :async,
      timestamp: timestamp,
      host: Tapper.Tracer.Server.endpoint_from_config(config)
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

    assert Enum.any?(annotations, fn(an) -> match?(%Tapper.Protocol.Annotation{value: :cs}, an) end)
    assert Enum.any?(annotations, fn(an) -> match?(%Tapper.Protocol.Annotation{value: :async}, an) end)

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