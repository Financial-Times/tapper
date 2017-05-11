defmodule Tapper.Tracer.Trace.Convert do
  @moduledoc "Converts Trace to Protocol spans."

  alias Tapper.Tracer.Trace
  alias Tapper.Protocol
  alias Tapper.Timestamp

  @spec to_protocol_spans(Trace.t) :: [%Protocol.Span{}]
  def to_protocol_spans(trace = %Trace{spans: spans}) do

    spans
    |> Map.values
    |> Enum.map(&(to_protocol_span(&1, trace)))
  end

  def to_protocol_span(span, %Trace{trace_id: {trace_id, _}, debug: debug, end_timestamp: trace_end_timestamp}) do

    duration = if is_nil(span.end_timestamp) do
      Timestamp.duration(span.start_timestamp, trace_end_timestamp)
    else
      Timestamp.duration(span.start_timestamp, span.end_timestamp)
    end

    %Protocol.Span{
      trace_id: trace_id,
      name: span.name,
      id: span.id,
      parent_id: span.parent_id,
      debug: debug,
      timestamp: Timestamp.to_absolute(span.start_timestamp),
      duration: max(duration, 1),
      annotations: to_protocol_annotations(span.annotations),
      binary_annotations: to_protocol_binary_annotations(span.binary_annotations)
    }
  end

  def to_protocol_annotations(annotations) when is_nil(annotations), do: []
  def to_protocol_annotations(annotations) when is_list(annotations) do
    Enum.map(annotations, &to_protocol_annotation/1)
  end

  def to_protocol_binary_annotations(binary_annotations) when is_nil(binary_annotations), do: []
  def to_protocol_binary_annotations(binary_annotations) when is_list(binary_annotations) do
    Enum.map(binary_annotations, &to_protocol_binary_annotation/1)
  end

  def to_protocol_annotation(annotation = %Trace.Annotation{}) do
    %Protocol.Annotation{
      timestamp: Timestamp.to_absolute(annotation.timestamp),
      value: annotation.value,
      host: to_protocol_endpoint(annotation.host)
    }
  end

  def to_protocol_binary_annotation(annotation = %Trace.BinaryAnnotation{}) do
    %Protocol.BinaryAnnotation{
      key: annotation.key,
      value: annotation.value,
      annotation_type: annotation.annotation_type,
      host: to_protocol_endpoint(annotation.host)
    }
  end

  def to_protocol_endpoint(nil), do: nil
  def to_protocol_endpoint(host = %Tapper.Endpoint{}) do
    endpoint = %Protocol.Endpoint{
      port: host.port || 0,
      service_name: host.service_name || "unknown"
    }

    case host.ip do
      {_, _, _, _} -> %{endpoint | ipv4: host.ip}
      {_, _, _, _, _, _, _, _} -> %{endpoint | ipv6: host.ip}
      _ -> endpoint
    end

  end

end
