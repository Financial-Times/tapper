defmodule Tapper.Protocol do
  @moduledoc """
  Defines the intermediate data structures used between the Tracer, and Reporters,
  containing only de-normalised fields relevant to the data transfer to trace collectors
  (e.g. Zipkin server), de-coupling from internal Tracer server state. In particular,
  protocol spans have a `duration`, rather than an `end_timestamp`.

  ## See also

  * `Tapper.Protocol.Span`
  * `Tapper.Protocol.Annotation`
  * `Tapper.Protocol.BinaryAnnotation`
  * `Tapper.Protocol.Endpoint`
  * `Tapper.Reporter.Api` - consumes protocol spans.
  """

  @type microseconds :: integer()
  @type timestamp :: microseconds()
  @type duration :: microseconds()

  defmodule Span do
    @moduledoc "A span, with hierarchy, start time, duration and annotations."

    alias Tapper.Protocol.Annotation
    alias Tapper.Protocol.BinaryAnnotation
    alias Tapper.Protocol

    defstruct [
      :trace_id,
      :name,
      :id,
      :parent_id,
      :annotations,
      :binary_annotations,
      :debug,
      :timestamp,
      :duration
    ]

    @type trace_id :: binary()
    @type span_id :: binary()

    @type t :: %__MODULE__{
      trace_id: trace_id(),
      id: span_id(),
      parent_id: span_id() | :root,
      annotations: [Annotation.t],
      binary_annotations: [BinaryAnnotation.t],
      debug: boolean,
      timestamp: Protocol.timestamp(),
      duration: Protocol.duration() | nil
    }
  end

  defmodule Annotation do
    @moduledoc "Annotation, with endpoint and timestamp."

    defstruct [
      :timestamp,
      :value,
      :host
    ]

    alias Tapper.Protocol.Endpoint
    alias Tapper.Protocol

    @type t :: %__MODULE__{
      timestamp: Protocol.timestamp(),
      value: String.t | atom(),
      host: Endpoint.t
    }
  end

  defmodule Endpoint do
    @moduledoc "Endpoint, with service name."

    defstruct [
      :ipv4,
      :port,
      :service_name,
      :ipv6
    ]

    @type ipv4 :: {integer(), integer(), integer(), integer()}
    @type ipv6 :: {integer(), integer(), integer(), integer(), integer(), integer(), integer(), integer()}

    @type t :: %__MODULE__{
      ipv4: ipv4(),
      port: integer(),
      service_name: String.t,
      ipv6: ipv6() | nil
    }
  end

  defmodule BinaryAnnotation do
    @moduledoc "Binary annotation with type, key, value, and endpoint."

    defstruct [
      :key,
      :value,
      :annotation_type,
      :host
    ]

    alias Tapper.Protocol.Endpoint

    @type t :: %__MODULE__{
      key: String.t | atom(),
      annotation_type: atom(),
      value: term(),
      host: Endpoint.t
    }
  end

end
