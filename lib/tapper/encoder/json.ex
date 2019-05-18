defmodule Tapper.Encoder.Json do
  @moduledoc """
  Encode protocol spans to JSON suitable for sending to V1 Zipkin Server API.

  V1 - [zipkin-api.yaml](https://github.com/openzipkin/zipkin-api/blob/682de48c7e1161f59d4e1ecfae0d631eea85ea44/zipkin-api.yaml)
  """

  @json_codec Application.get_env(:tapper, :json_codec, Jason)

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

    @json_codec.encode_to_iodata!(map)
  end

  def encode_trace_id(map, %Tapper.Protocol.Span{trace_id: trace_id}) do
    put_in(map, [:traceId], trace_id)
  end

  def encode_span_id(map, span) do
    put_in(map, [:id], span.id)
  end

  def encode_parent_id(map, span) do
    case span.parent_id do
      :root -> map
      _ -> put_in(map, [:parentId], span.parent_id)
    end
  end

  def encode_annotations(map, %Tapper.Protocol.Span{annotations: annotations}) when is_nil(annotations), do: map
  def encode_annotations(map, span) do
    put_in(map, [:annotations], Enum.map(span.annotations, &encode_annotation/1))
  end

  def encode_annotation(%Tapper.Protocol.Annotation{value: value, host: host, timestamp: timestamp}) do
    %{
      value: to_string(value),
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

  @spec encode_binary_annotation_value(atom(), boolean() | binary()) :: boolean() | binary()
  def encode_binary_annotation_value(:bool, value) when value in [true, false], do: value
  def encode_binary_annotation_value(:bool, value), do: !!value
  def encode_binary_annotation_value(:string, value) when is_binary(value), do: value
  def encode_binary_annotation_value(:bytes, value) when is_binary(value), do: Base.encode64(value)
  def encode_binary_annotation_value(_type, value), do: to_string(value)

  def encode_binary_annotation_type(annotation, type) when type in [:bool, :i16, :i32, :i64, :double, :bytes] do
    put_in(annotation[:type], String.upcase(Atom.to_string(type)))
  end
  def encode_binary_annotation_type(annotation, _type), do: annotation

  def encode_endpoint(%Tapper.Protocol.Endpoint{ipv4: ipv4, ipv6: ipv6, port: port, service_name: service_name}) do
    %{}
    |> add_service_name(service_name)
    |> add_port(port)
    |> add_ipv4(ipv4)
    |> add_ipv6(ipv6)
  end

  def add_service_name(map, "unknown"), do: put_in(map, [:serviceName], "")
  def add_service_name(map, :unknown), do: put_in(map, [:serviceName], "")
  def add_service_name(map, nil), do: put_in(map, [:serviceName], "")
  def add_service_name(map, "" <> serviceName) do
    put_in(map, [:serviceName], String.downcase(serviceName))
  end
  def add_service_name(map, service_name) when is_atom(service_name) do
    put_in(map, [:serviceName], String.downcase(Atom.to_string(service_name)))
  end

  def add_port(map, port) when is_nil(port), do: map
  def add_port(map, port) when is_integer(port), do: put_in(map, [:port], port)

  def add_ipv4(map, ipv4) when is_nil(ipv4), do: map
  def add_ipv4(map, ipv4 = {_, _, _, _}) do
    put_in(map, [:ipv4], List.to_string(:inet_parse.ntoa(ipv4)))
  end

  def add_ipv6(map, ipv6) when is_nil(ipv6), do: map
  def add_ipv6(map, ipv6 = {_, _, _, _, _, _, _, _}) do
    put_in(map, [:ipv6], List.to_string(:inet_parse.ntoa(ipv6)))
  end
end
