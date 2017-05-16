defmodule Tapper.Tracer.Trace do
  @moduledoc "Tracer internal state, and functions to convert this to protocol spans (Tapper.Protocol)"

  alias Tapper.Timestamp

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
    timestamp: Timestamp.timestamp(),
    end_timestamp: Timestamp.timestamp(),
    last_activity: Timestamp.timestamp(),
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

    @type t :: %__MODULE__{
      name: String.t,
      id: Tapper.SpandId.t,
      parent_id: Tapper.SpandId.t,
      start_timestamp: Timestamp.timestamp(),
      end_timestamp: Timestamp.timestamp(),
      annotations: [Annotation.t],
      binary_annotations: [BinaryAnnotation.t]
    }
  end

  defmodule Annotation do
    @moduledoc false

    defstruct [
      :timestamp,
      :value,
      :host
    ]

    @type t :: %__MODULE__{
      timestamp: Timestamp.timestamp(),
      value: atom() | String.t,
      host: Tapper.Endpoint.t | nil
    }

    def new(value, timestamp, endpoint = %Tapper.Endpoint{}) when is_tuple(timestamp) do
      %__MODULE__{
        value: value,
        timestamp: timestamp,
        host: endpoint
      }
    end

    def new(value, timestamp) when is_tuple(timestamp) do
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

    @type annotation_type :: :string | :bool | :i16 | :i32 | :i64 | :double | :bytes

    @type t :: %__MODULE__{
      key: atom() | String.t,
      value: any(),
      annotation_type: annotation_type(),
      host: Tapper.Endpoint.t | nil
    }

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

  def has_annotation?(trace = %__MODULE__{}, span_id, value), do: has_annotation?(trace.spans[span_id], value)

  def has_annotation?(nil, _value), do: false

  def has_annotation?(%__MODULE__.SpanInfo{annotations: annotations}, value) do
    Enum.any?(annotations, fn(annotation) -> annotation.value === value end)
  end

end
