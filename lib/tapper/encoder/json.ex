defmodule Tapper.Encoder.Json do
    
    @spec encode!([%Tapper.Protocol.Span{}]) :: iodata | no_return
    def encode!(spans = [%Tapper.Protocol.Span{} | _spans ]) do
        [?[, Enum.intersperse(Enum.map(spans, &encode(&1)), ?,), ?]]
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
            |> encode_annotations(span)

        Poison.encode_to_iodata!(map)
    end

    def encode_trace_id(map, %Tapper.Protocol.Span{trace_id: trace_id}) do
        put_in(map, [:traceId], Tapper.Id.Utils.to_hex(trace_id))
    end

    def encode_span_id(map, span) do
        put_in(map, [:id], Tapper.Id.Utils.to_hex(span.id))
    end

    def encode_parent_id(map, span) do
        case span.parent_id do
            :root -> map
            _ -> put_in(map, [:parentId], Tapper.Id.Utils.to_hex(span.parent_id))
        end
    end

    def encode_annotations(map, %Tapper.Protocol.Span{annotations: annotations}) when is_nil(annotations), do: map
    def encode_annotations(map, span) do
        put_in(map, [:annotations], Enum.map(span.annotations, &encode_annotation/1))
    end

    def encode_annotation(%Tapper.Protocol.Annotation{value: value, host: host, timestamp: timestamp}) do
        %{
            value: value,
            endpoint: encode_endpoint(host),
            timestamp: timestamp
        }
    end

    def encode_endpoint(%Tapper.Protocol.Endpoint{ipv4: ipv4, port: port, service_name: service_name}) do
        %{
            serviceName: service_name
        } 
        |> add_port(port)
        |> add_ipv4(ipv4)
        # TODO ipv6
    end

    def add_port(map, port) when is_nil(port), do: map
    def add_port(map, port) when is_integer(port), do: put_in(map, [:port], port)

    def add_ipv4(map, ipv4) when is_nil(ipv4), do: map
    def add_ipv4(map, {a,b,c,d}) do
        put_in(map, [:ipv4], "#{a}.#{b}.#{c}.#{d}")
    end

end