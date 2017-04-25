defmodule TracerTest do
  use ExUnit.Case
  doctest Tapper.Tracer

  test "start root trace starts process" do
    id = Tapper.Tracer.start(debug: true)

    state = :sys.get_state(Tapper.Tracer.Server.via_tuple(id))

    assert state.trace_id == id.trace_id
    assert state.span_id == id.span_id
    assert state.parent_id == :root

    [{pid,_}] = Tapper.Tracer.whereis(id.trace_id)
    assert Process.alive?(pid)
  end

  test "end root trace causes trace server to exit" do
      id = Tapper.Tracer.start(debug: true)

      [{pid,_}] = Tapper.Tracer.whereis(id.trace_id)
      ref = Process.monitor(pid)
      
      Tapper.Tracer.finish(id)

      assert_receive {:DOWN, ^ref, _, _, _}, 1000
  end

  test "start_span, finish_span returns to previous id" do
      trace = Tapper.Tracer.start(debug: true, name: "main-span")
      start_span = Tapper.Tracer.start_span(trace, name: "sub-span")
      finish_span = Tapper.Tracer.finish_span(start_span)

      assert trace.trace_id == start_span.trace_id
      assert trace.trace_id == finish_span.trace_id
      
      assert trace.span_id == finish_span.span_id

      assert start_span.span_id != trace.span_id
      assert start_span.span_id != finish_span.span_id

      assert start_span.parent_ids == [trace.span_id]
      assert finish_span.parent_ids == []      
  end

end