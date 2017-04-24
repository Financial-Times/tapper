defmodule Tapper.Encoder.Json do
    
    @spec encode!([%Tapper.Protocol.Span{}]) :: iodata | no_return
    def encode!(spans = [%Tapper.Protocol.Span{} | _spans ]) do
        [?[, Enum.map(spans, &encode(&1)), ?]]
    end
    
    @spec encode!(%Tapper.Protocol.Span{}) :: iodata | no_return
    def encode(span = %Tapper.Protocol.Span{}) do
        map = Map.take(span, [
            :name,
            :debug,
            :timestamp,
            :duration,
            ])

        map = map
            |> encode_trace_id(span)
            |> encode_span_id(span)
            |> encode_parent_id(span)

        Poison.encode_to_iodata!(map)
    end

    def encode_trace_id(map, %Tapper.Protocol.Span{trace_id: trace_id}) do
        put_in(map, [:trace_id], Tapper.Id.Utils.to_hex(trace_id))
    end

    def encode_span_id(map, span) do
        put_in(map, [:id], Tapper.Id.Utils.to_hex(span.id))
    end

    def encode_parent_id(map, span) do
        case span.parent_id do
            :root -> map
            _ -> put_in(map, [:parent_id], Tapper.Id.Utils.to_hex(span.parent_id))
        end
    end

end