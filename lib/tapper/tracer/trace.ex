defmodule Tapper.Tracer.Trace do
  @moduledoc "Tracer internal state, and functions to convert this to protocol spans (Tapper.Protocol)"

  alias Tapper.Protocol

  @doc "Tracer state: the state of a single trace session."
  defstruct [
    :config,        # configuration from supervisor
    :trace_id,      # root trace_id
    :span_id,       # root span id
    :parent_id,     # parent of trace, or :root if new root trace
    :sample,        # we are sampling this trace
    :debug,         # we are debugging this trace

    :spans,         # map of spans in this trace
    :timestamp,     # start of trace
    :end_timestamp, # end of trace
    :last_activity, # last time a span was started, ended or updated
    :ttl,           # time to live in ms, past last_activity
    :async          # this trace will finish asynchronously
  ]

  @type trace :: %__MODULE__{
    trace_id: Tapper.TraceId.t,
    span_id: Tapper.SpanId.t,
    parent_id: Tapper.SpanId.t | :root,
    spans: %{required(Tapper.SpanId.t) => Tapper.Traceer.SpanInfo.t},
    config: map(),
    sample: boolean(),
    debug: boolean(),
    timestamp: integer(),
    end_timestamp: integer(),
    last_activity: integer(),
    ttl: integer(),
    async: nil | true
  }
  @type t :: trace

  defmodule SpanInfo do
    @moduledoc false

    defstruct [
      :name,
      :id,
      :parent_id,
      :start_timestamp,
      :end_timestamp,
      :annotations,
      :binary_annotations
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Annotation do
    @moduledoc false

    defstruct [
      :timestamp,
      :value,
      :host
    ]

    @type t :: %__MODULE__{timestamp: integer(), value: atom() | String.t, host: Tapper.Endpoint.t | nil}

    def new(value, timestamp, endpoint = %Tapper.Endpoint{}) when is_integer(timestamp) do
      %__MODULE__{
        value: value,
        timestamp: timestamp,
        host: endpoint
      }
    end

    def new(value, timestamp) when is_integer(timestamp) do
      %__MODULE__{
        value: value,
        timestamp: timestamp
      }
    end
  end

  defmodule BinaryAnnotation do
    @moduledoc false
    defstruct [
      :key,
      :value,
      :annotation_type,
      :host # optional
    ]

    @type t :: %__MODULE__{key: atom() | String.t, value: any(), annotation_type: atom(), host: Tapper.Endpoint.t | nil}

    @types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

    def new(key, value, type, endpoint = %Tapper.Endpoint{}) when type in @types do
      %__MODULE__{
        key: key,
        value: value,
        annotation_type: type,
        host: endpoint
      }
    end

    def new(key, value, type) when type in @types do
      %__MODULE__{
        key: key,
        value: value,
        annotation_type: type,
      }
    end
  end

  @spec endpoint_from_config(map()) :: Tapper.Endpoint.t
  def endpoint_from_config(%{host_info: %{ip: ip, system_id: system_id}}) do
    %Tapper.Endpoint{
        service_name: system_id,
        ip: ip,
        port: 0
    }
  end

  @spec to_protocol_spans(__MODULE__.t) :: [%Protocol.Span{}]
  def to_protocol_spans(%__MODULE__{trace_id: trace_id, debug: debug, spans: spans, end_timestamp: end_timestamp}) do

    {trace_id, _} = trace_id

    spans
    |> Map.values
    |> Enum.map(fn(span) ->

      duration = if(is_nil(span.end_timestamp), do: end_timestamp - span.start_timestamp, else: span.end_timestamp - span.start_timestamp)

      %Protocol.Span{
        trace_id: trace_id,
        name: span.name,
        id: span.id,
        parent_id: span.parent_id,
        debug: debug,
        timestamp: span.start_timestamp,
        duration: max(duration, 1),
        annotations: to_protocol_annotations(span.annotations),
        binary_annotations: to_protocol_binary_annotations(span.binary_annotations)
      }
    end)
  end

  def to_protocol_annotations(annotations) when is_nil(annotations), do: []
  def to_protocol_annotations(annotations) when is_list(annotations) do
    Enum.map(annotations, &to_protocol_annotation/1)
  end

  def to_protocol_binary_annotations(binary_annotations) when is_nil(binary_annotations), do: []
  def to_protocol_binary_annotations(binary_annotations) when is_list(binary_annotations) do
    Enum.map(binary_annotations, &to_protocol_binary_annotation/1)
  end

  def to_protocol_annotation(annotation = %__MODULE__.Annotation{}) do
    %Protocol.Annotation{
      timestamp: annotation.timestamp,
      value: annotation.value,
      host: to_protocol_endpoint(annotation.host)
    }
  end

  def to_protocol_binary_annotation(annotation = %__MODULE__.BinaryAnnotation{}) do
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
