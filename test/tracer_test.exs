defmodule TracerTest do
  use ExUnit.Case
  doctest Tapper.Tracer

  import Test.Helper.Server

  alias Tapper.Tracer

  test "start root trace starts process" do
    id = Tracer.start(debug: true)

    state = :sys.get_state(Tracer.Server.via_tuple(id))

    assert state.trace_id == id.trace_id
    assert state.span_id == id.span_id
    assert state.parent_id == :root

    [{pid, _}] = Tracer.whereis(id.trace_id)
    assert Process.alive?(pid)
  end

  test "end root trace causes trace server to exit" do
    id = Tracer.start(debug: true)

    [{pid, _}] = Tracer.whereis(id.trace_id)
    ref = Process.monitor(pid)

    Tracer.finish(id)

    assert Logger.metadata() == []
    assert_receive {:DOWN, ^ref, _, _, _}, 1000
  end

  test "start_span, finish_span returns to previous id" do
    trace = Tracer.start(debug: true, name: "main-span")
    start_span = Tracer.start_span(trace, name: "sub-span")
    finish_span = Tracer.finish_span(start_span)

    assert trace.trace_id == start_span.trace_id
    assert trace.trace_id == finish_span.trace_id

    assert trace.span_id == finish_span.span_id

    assert start_span.span_id != trace.span_id
    assert start_span.span_id != finish_span.span_id

    assert start_span.parent_ids == [trace.span_id]
    assert finish_span.parent_ids == []
  end

  test "add binary_annotation returns same id" do
    {ref, reporter} = msg_reporter()

    id1 = Tracer.start(debug: true, name: "main-span", reporter: reporter)
    id2 = Tracer.update_span(id1, [Tracer.binary_annotation_delta(:string, "test", "value")])

    assert id1 == id2
    assert %Tapper.Id{} = id1

    Tracer.finish(id2)

    assert_receive {^ref, spans}, 5000
    assert is_list(spans)
  end

  test "add annotation returns same id" do
    {ref, reporter} = msg_reporter()

    id1 = Tracer.start(debug: true, name: "main-span", reporter: reporter)
    id2 = Tracer.update_span(id1, [Tracer.annotation_delta(:cr)])

    assert id1 == id2
    assert %Tapper.Id{} = id1

    Tracer.finish(id2)

    assert_receive {^ref, spans}, 5000
    assert is_list(spans)
  end

  test "ignored id" do
    assert :ignore == Tracer.start_span(:ignore)
    assert :ignore == Tracer.finish_span(:ignore)
    assert :ignore == Tracer.update_span(:ignore, [Tracer.name_delta("name")])
  end
end
