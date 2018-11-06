defmodule Tapper.Tracer.Trace.Convert do
  @moduledoc "Converts Trace to Protocol spans."

  alias Tapper.Tracer.Trace
  alias Tapper.Protocol
  alias Tapper.Timestamp

  @doc "convert an internal trace to a list of protocol spans"
  @spec to_protocol_spans(Trace.t) :: [%Protocol.Span{}]
  def to_protocol_spans(trace = %Trace{spans: spans}) do

    spans
    |> Map.values
    |> Enum.map(&(to_protocol_span(&1, trace)))
  end

  @doc "convert an internal span to a protocol span, setting duration"
  def to_protocol_span(span, trace = %Trace{trace_id: trace_id, debug: debug}) do

    duration = span_duration(span, trace)

    %Protocol.Span{
      trace_id: trace_id,
      name: span.name,
      id: span.id,
      parent_id: span.parent_id,
      debug: debug,
      timestamp: Timestamp.to_absolute(span.start_timestamp),
      duration: duration,
      annotations: to_protocol_annotations(span.annotations),
      binary_annotations: to_protocol_binary_annotations(span.binary_annotations)
    }
  end

  @doc """
  calculate span duration.

  Handles special cases of:
    * shared spans, for which we force a `nil` duration (http://zipkin.io/pages/instrumenting.html#timestamps-and-duration)
    * spans which were never formally closed, which get the trace's `end_timestamp`
    * calculated durations < 1 microsecond, which we round up to 1 microsecond
  """
  @spec span_duration(span :: Trace.SpanInfo.t, trace :: Trace.t) :: nil | pos_integer()
  def span_duration(span, trace)

  def span_duration(%Trace.SpanInfo{shared: true}, _trace), do: nil

  def span_duration(%Trace.SpanInfo{start_timestamp: start_timestamp, end_timestamp: nil}, %Trace{end_timestamp: trace_end_timestamp}) do
    max(Timestamp.duration(start_timestamp, trace_end_timestamp), 1)
  end

  def span_duration(%Trace.SpanInfo{start_timestamp: start_timestamp, end_timestamp: end_timestamp}, _trace) do
    max(Timestamp.duration(start_timestamp, end_timestamp), 1)
  end

  @doc false
  def to_protocol_annotations(annotations) when is_nil(annotations), do: []
  def to_protocol_annotations(annotations) when is_list(annotations) do
    Enum.map(annotations, &to_protocol_annotation/1)
  end

  @doc false
  def to_protocol_binary_annotations(binary_annotations) when is_nil(binary_annotations), do: []
  def to_protocol_binary_annotations(binary_annotations) when is_list(binary_annotations) do
    Enum.map(binary_annotations, &to_protocol_binary_annotation/1)
  end

  @doc false
  def to_protocol_annotation(annotation = %Trace.Annotation{}) do
    %Protocol.Annotation{
      timestamp: Timestamp.to_absolute(annotation.timestamp),
      value: annotation.value,
      host: to_protocol_endpoint(annotation.host)
    }
  end

  @doc false
  def to_protocol_binary_annotation(annotation = %Trace.BinaryAnnotation{}) do
    %Protocol.BinaryAnnotation{
      key: annotation.key,
      value: annotation.value,
      annotation_type: annotation.annotation_type,
      host: to_protocol_endpoint(annotation.host)
    }
  end

  @doc false
  def to_protocol_endpoint(nil), do: nil
  def to_protocol_endpoint(host = %Tapper.Endpoint{}) do
    endpoint = %Protocol.Endpoint{
      port: host.port || 0,
      service_name: host.service_name || :unknown
    }

    host = Tapper.Endpoint.resolve(host)

    case host.ip do
      ip when is_tuple(ip) and tuple_size(ip) == 4 -> %{endpoint | ipv4: ip}
      ip when is_tuple(ip) and tuple_size(ip) == 8 -> %{endpoint | ipv6: ip}
      _ -> endpoint
    end

  end

end
