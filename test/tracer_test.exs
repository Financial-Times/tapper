defmodule TracerTest do
  use ExUnit.Case
  doctest Tapper.Tracer

  test "start root trace starts process" do
    id = Tapper.Tracer.start(debug: true)

    state = :sys.get_state(Tapper.Tracer.via_tuple(id))

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

  # test "enter span" do
  #     trace = Tapper.Tracer.start_trace()
  #     span = Tapper.Tracer.start_span(trace)
  #     end_span = Tapper.TraceId.end_span(span)

  #     assert trace.trace_id == span.trace_id == end_span.trace_id
  #     assert trace.span_id == end_span.span_id
  #     assert span.span_id != trace.span_id
  #     assert span.span_id != end_span.span_id
  # end

end