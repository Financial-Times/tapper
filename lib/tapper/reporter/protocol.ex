defmodule Tapper.Protocol do
  @moduledoc """
    Defines the intermediate data structures used between the Tracer, and Reporters,
    containing only de-normalised fields relevant to the data transfer to trace collectors
    (e.g. Zipkin server), de-coupling from internal Tracer server state.
  """

  defmodule Span do

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

    @type trace_id :: integer()
    @type span_id :: integer()

    @type timestamp :: integer()
    @type duration :: integer()

    @type t :: %__MODULE__{trace_id: trace_id(), id: span_id(), parent_id: span_id(), annotations: [Annotation.t], binary_annotations: [BinaryAnnotation.t], debug: boolean, timestamp: timestamp(), duration: duration() }
  end

  defmodule Annotation do
    defstruct [
      :timestamp,
      :value,
      :host
    ]

    @type timestamp :: Tapper.Span.timestamp()


    @type t :: %__MODULE__{timestamp: timestamp(), value: String.t | atom(), host: Endpoint.t}
  end

  defmodule Endpoint do
    defstruct [
      :ipv4,
      :port,
      :service_name,
      :ipv6
    ]

    @type ipv4 :: {integer(), integer(), integer(), integer()}
    @type ipv6 :: binary()

    @type t :: %__MODULE__{ipv4: ipv4(), port: integer(), service_name: String.t, ipv6: ipv6() | nil}
  end

  defmodule BinaryAnnotation do
    defstruct [
      :key,
      :value,
      :annotation_type,
      :host
    ]

    @type t :: %__MODULE__{}
  end

end