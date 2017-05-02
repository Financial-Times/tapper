defmodule Tracer.Server.InitTest do
  use ExUnit.Case

  import Test.Helper.Server

  test "init, no options" do
    config = config()
    trace_id = Tapper.TraceId.generate()
    span_id = Tapper.SpanId.generate()
    timestamp = System.os_time(:microseconds)

    {:ok, trace, ttl} = Tapper.Tracer.Server.init([config, {trace_id, span_id, :root, true, false}, self(), timestamp, []])

    assert trace.trace_id == trace_id
    assert trace.span_id == span_id
    assert trace.parent_id == :root
    assert trace.sample == true
    assert trace.debug == false

    assert trace.timestamp == timestamp
    assert trace.last_activity == timestamp
    assert trace.end_timestamp == nil

    assert ttl == 30_000
    assert ttl == trace.ttl

    assert is_map(trace.spans)
    assert Map.keys(trace.spans) == [span_id]
    span = trace.spans[span_id]

    assert span.id == span_id
    assert span.parent_id == :root
    assert span.start_timestamp == timestamp
    assert span.end_timestamp == nil
    assert span.name == "unknown"

    annotations = span.annotations
    assert is_list(annotations)
    assert length(annotations) == 1

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
        timestamp: timestamp,
        value: :cs,
        host: Tapper.Tracer.Server.endpoint_from_config(config)
    }

    assert span.binary_annotations == []
  end

  test "init, ttl: ttl; sets ttl" do
    ttl = :rand.uniform(1000)

    config = config()
    trace_id = Tapper.TraceId.generate()
    span_id = Tapper.SpanId.generate()
    timestamp = System.os_time(:microseconds)

    {:ok, trace, ^ttl} = Tapper.Tracer.Server.init([config, {trace_id, span_id, :root, true, false}, self(), timestamp, [ttl: ttl]])

    assert trace.ttl == ttl
  end

  test "init, type: server; adds :sr annotation" do
    {trace, span_id} = init_with_opts(type: :server)

    span = trace.spans[span_id]
    annotations = trace.spans[span_id].annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
        timestamp: trace.timestamp,
        value: :sr,
        host: Tapper.Tracer.Server.endpoint_from_config(trace.config)
    }

    assert span.binary_annotations == []
  end

  test "init, type: client; adds :cs annotation" do
    {trace, span_id} = init_with_opts(type: :client)

    span = trace.spans[span_id]
    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
        timestamp: trace.timestamp,
        value: :cs,
        host: Tapper.Tracer.Server.endpoint_from_config(trace.config)
    }

    assert span.binary_annotations == []
  end

  test "init, type: client, remote: endpoint; adds server address binary annotation" do
    remote = random_endpoint()
    {trace, span_id} = init_with_opts(type: :client, remote: remote)

    span = trace.spans[span_id]
    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
        timestamp: trace.timestamp,
        value: :cs,
        host: Tapper.Tracer.Server.endpoint_from_config(trace.config)
    }

    binary_annotations = span.binary_annotations
    assert length(binary_annotations) == 1
    assert hd(binary_annotations) == %Tapper.Tracer.Trace.BinaryAnnotation{
        annotation_type: :bool,
        key: :sa,
        value: true,
        host: remote
    }
  end

  test "init, type: server, remote: endpoint adds client address binary annotation" do
    remote = random_endpoint()
    {trace, span_id} = init_with_opts(type: :server, remote: remote)

    span = trace.spans[span_id]
    annotations = span.annotations
    assert length(annotations) == 1

    assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
        timestamp: trace.timestamp,
        value: :sr,
        host: Tapper.Tracer.Server.endpoint_from_config(trace.config)
    }

    binary_annotations = span.binary_annotations
    assert length(binary_annotations) == 1
    assert hd(binary_annotations) == %Tapper.Tracer.Trace.BinaryAnnotation{
        annotation_type: :bool,
        key: :ca,
        value: true,
        host: remote
    }
  end

  test "init with name: name" do
    {trace, span_id} = init_with_opts(name: "name")

    assert trace.spans[span_id].name == "name"
  end

  test "init with name, then rename span" do
    {trace, span_id} = init_with_opts(name: "name")

    assert trace.spans[span_id].name == "name"

    timestamp = System.os_time(:microseconds)

    {:noreply, state, _ttl} =
        Tapper.Tracer.Server.handle_cast({:name, span_id, "new-name", timestamp}, trace)

    assert state.spans[span_id].name == "new-name"
    assert state.last_activity == timestamp
  end
end