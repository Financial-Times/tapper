defmodule JsonTest do
    use ExUnit.Case

    test "encode with parent_id, no annotations" do
        trace_id = {hi, lo, _} = Tapper.TraceId.generate()
        span_id = Tapper.SpanId.generate()
        parent_span_id = Tapper.SpanId.generate()

        proto_span = %Tapper.Protocol.Span{
            trace_id: lo,
            trace_id_high: hi,
            id: span_id,
            parent_id: parent_span_id,
            name: "test",
            timestamp: 1234,
            duration: 100,
            debug: true
        }

        json = Tapper.Encoder.Json.encode!([proto_span])

        IO.inspect json

        assert is_list(json)
        assert json == [91,
            [[123,
            [[34, ["trace_id"], 34], 58, [34, [Tapper.TraceId.to_hex(trace_id)], 34],
                44, [34, ["timestamp"], 34], 58, "1234", 44, [34, ["parent_id"], 34], 58,
                [34, [Tapper.SpanId.to_hex(parent_span_id)], 34], 44, [34, ["name"], 34], 58,
                [34, ["test"], 34], 44, [34, ["id"], 34], 58,
                [34, [Tapper.SpanId.to_hex(span_id)], 34], 44, [34, ["duration"], 34], 58, "100", 44,
                [34, ["debug"], 34], 58, "true"], 125]], 
        93]
    end

    test "encode parent_id with root parent_id" do
        map = Tapper.Encoder.Json.encode_parent_id(%{}, %Tapper.Protocol.Span{parent_id: :root})
        assert map == %{}
    end

    test "encode 64-bit trace_id" do
        map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: 1234, trace_id_high: 0})
        assert map == %{trace_id: "00000000000004D2"}
    end

    test "encode 128-bit trace_id" do
        <<trace_id_low :: size(64)>> = <<0,255,255,255,255,255,255,255>>
        <<trace_id_high :: size(64)>> = <<0,255,255,255,255,255,255,255>>

        map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: trace_id_low, trace_id_high: trace_id_high})
        assert map == %{trace_id: "00FFFFFFFFFFFFFF00FFFFFFFFFFFFFF"}
    end

end