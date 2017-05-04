defmodule Tapper.Encoder.Json do
  @moduledoc "Encode protocol spans to JSON suitable for sending to Zipkin Server API"

  @spec encode!([%Tapper.Protocol.Span{}]) :: iodata | no_return
  def encode!(spans = [%Tapper.Protocol.Span{} | _spans]) do
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
      |> encode_binary_annotations(span)

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

    def encode_binary_annotations(map, %Tapper.Protocol.Span{binary_annotations: annotations}) when is_nil(annotations), do: map
    def encode_binary_annotations(map, span) do
      put_in(map, [:binaryAnnotations], Enum.map(span.binary_annotations, &encode_binary_annotation/1))
    end

    def encode_binary_annotation(%Tapper.Protocol.BinaryAnnotation{key: key, value: value, annotation_type: type, host: host}) do
      %{
        key: key,
        value: encode_binary_annotation_value(type, value),
        endpoint: encode_endpoint(host)
      }
      |> encode_binary_annotation_type(type)
    end


    @max_safe_integer_value 9_007_199_254_740_991
    @max_64_bit_value 18_446_744_073_709_551_615

    def encode_binary_annotation_value(type, value) when type in [:bool, :double, :string], do: value
    def encode_binary_annotation_value(:i16, value) when value < 32_768, do: value
    def encode_binary_annotation_value(:i16, _value), do: raise ArgumentError, "Value out of range for 16-bit integer"

    def encode_binary_annotation_value(:i32, value) when value < 4_294_967_296, do: value
    def encode_binary_annotation_value(:i32, _value), do: raise ArgumentError, "Value out of range for 32-bit integer"

    def encode_binary_annotation_value(:i64, value) when value <= @max_safe_integer_value, do: value
    def encode_binary_annotation_value(:i64, value) when value > @max_safe_integer_value and value < @max_64_bit_value, do: Integer.to_string(value)
    def encode_binary_annotation_value(:i64, _value), do: raise ArgumentError, "Value out of range for 64-bit integer"

    def encode_binary_annotation_value(:bytes, value) when is_binary(value) do
      Base.encode64(value)
    end

    def encode_binary_annotation_type(annotation, :string), do: annotation
    def encode_binary_annotation_type(annotation, type) when type in [:bool, :i16, :i32, :i64, :double, :bytes] do
      put_in(annotation[:type], String.upcase(Atom.to_string(type)))
    end

    def encode_endpoint(%Tapper.Protocol.Endpoint{ipv4: ipv4, port: port, service_name: service_name}) do
      %{
        serviceName: service_name || "unknown"
      }
      |> add_port(port)
      |> add_ipv4(ipv4)
      # TODO ipv6
    end

    def add_port(map, port) when is_nil(port), do: map
    def add_port(map, port) when is_integer(port), do: put_in(map, [:port], port)

    def add_ipv4(map, ipv4) when is_nil(ipv4), do: map
    def add_ipv4(map, {a, b, c, d}) do
      put_in(map, [:ipv4], "#{a}.#{b}.#{c}.#{d}")
    end

  end