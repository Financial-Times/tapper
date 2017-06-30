defmodule Tapper.Id do
  @moduledoc """
  The ID used with the API; tracks nested spans.

  > Clients should consider this ID opaque!

  Use `destructure/1` to obtain trace parameters. NB special value `:ignore` produces no-ops in API functions.
  """

  defstruct [
    trace_id: nil,
    span_id: nil,
    origin_parent_id: :root, # root span from incoming trace, or :root
    parent_ids: [],          # stack of child spans
    sample: false,           # incoming trace sampled flag, or sample decision
    debug: false,            # incoming trace debug flag, or debug option
    sampled: false           # i.e. sample || debug
  ]

  alias Tapper.TraceId
  alias Tapper.SpanId

  @typedoc false
  @type t :: %__MODULE__{trace_id: Tapper.TraceId.t, span_id: Tapper.SpanId.t, parent_ids: [Tapper.SpanId.t], sampled: boolean(), origin_parent_id: Tapper.SpanId.t | :root, sample: boolean(), debug: boolean()} | :ignore

  @doc "Create id from trace parameters"
  @spec init(trace_id :: TraceId.t, span_id :: SpanId.t, parent_span_id :: SpanId.t, sample :: boolean, debug :: boolean) :: t
  def init(trace_id, span_id, parent_span_id, sample, debug) do
    %Tapper.Id{
      trace_id: trace_id,
      span_id: span_id,
      origin_parent_id: parent_span_id,
      parent_ids: [],
      sample: sample,
      debug: debug,
      sampled: sample || debug
    }
  end

  @doc "is the trace with this id being sampled?"
  @spec sampled?(id :: t) :: boolean
  def sampled?(%Tapper.Id{sampled: sampled}), do: sampled

  @doc "Push the current span id onto the parent stack, and set new span id, returning updated Tapper Id"
  @spec push(Tapper.Id.t, Tapper.SpanId.t) :: Tapper.Id.t
  def push(id = %Tapper.Id{}, span_id) do
    %Tapper.Id{id | parent_ids: [id.span_id | id.parent_ids], span_id: span_id}
  end

  @doc "Pop the last parent span id from the parent stack, returning updated Tapper Id"
  @spec pop(Tapper.Id.t) :: Tapper.Id.t
  def pop(id = %Tapper.Id{parent_ids: []}), do: id
  def pop(id = %Tapper.Id{parent_ids: [parent_id | parent_ids]}) do
    %Tapper.Id{id | parent_ids: parent_ids, span_id: parent_id}
  end

  @doc """
  Destructure the id into external hex notation, for trace propagation purposes.

  ## Example
  ```
  id = Tapper.start()

  {trace_id_hex, span_id_hex, parent_span_id_hex, sampled_flag, debug_flag} =
    Tapper.Id.destructure(id)
  ```
  """
  @spec destructure(Tapper.Id.t) :: {String.t, String.t, String.t, boolean, boolean}
  def destructure(%Tapper.Id{trace_id: trace_id, span_id: span_id, origin_parent_id: :root, parent_ids: [], sample: sample, debug: debug}) do
    {TraceId.to_hex(trace_id), SpanId.to_hex(span_id), "", sample, debug}
  end
  def destructure(%Tapper.Id{trace_id: trace_id, span_id: span_id, origin_parent_id: origin_parent_id, parent_ids: [], sample: sample, debug: debug}) do
    {TraceId.to_hex(trace_id), SpanId.to_hex(span_id), SpanId.to_hex(origin_parent_id), sample, debug}
  end
  def destructure(%Tapper.Id{trace_id: trace_id, span_id: span_id, origin_parent_id: _origin_parent_id, parent_ids: [parent_id | _rest], sample: sample, debug: debug}) do
    {TraceId.to_hex(trace_id), SpanId.to_hex(span_id), SpanId.to_hex(parent_id), sample, debug}
  end

  @doc "Generate a TraceId for testing; sample is true"
  def test_id(parent_span_id \\ :root) do
    %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: [],
      origin_parent_id: parent_span_id,
      sample: true,
      debug: false,
      sampled: true
    }
  end

  defimpl Inspect do
    import Inspect.Algebra
    @doc false
    def inspect(id, _opts) do
      sampled = if(id.sampled, do: "SAMPLED", else: "-")
      concat ["#Tapper.Id<", Tapper.TraceId.format(id.trace_id), ":", Tapper.SpanId.format(id.span_id), ",", sampled, ">"]
    end
  end

  defimpl String.Chars do
    @doc false
    def to_string(id) do
      sampled = if(id.sampled, do: "S+", else: "S-")
      sample = if(id.sample, do: "s+", else: "s-")
      debug = if(id.debug, do: "d+", else: "d-")
      "T" <> Tapper.TraceId.to_hex(id.trace_id) <> ",S" <> Tapper.SpanId.to_hex(id.span_id) <> "," <> sampled <> "," <> sample <> "," <> debug
    end
  end

end

defmodule Tapper.TraceId do
  @moduledoc """
  Generate, parse or format a top-level trace id.

  The TraceId comprises the 128-bit Zipkin id, with a second component which is generated using a
  per-VM unique number sequence, to disambiguate parallel requests to the same server, so each request
  gets it's own trace server, which prevents lifecycle confusion.
  """
  @type int128 :: integer()

  @type t :: {int128, integer()}

  @doc "generate a trace id"
  @spec generate() :: t
  def generate() do
    <<id :: size(128)>> = :crypto.strong_rand_bytes(16)
    {id, uniq()}
  end

  @doc "format a trace id for logs etc."
  @spec format(trace_id :: t) :: String.t
  def format(trace_id)
  def format({id, unique}) do
    "#Tapper.TraceId<" <> Tapper.Id.Utils.to_hex(id) <> "." <> Integer.to_string(unique) <> ">"
  end

  @doc "format a trace id to a hex string, for propagation etc."
  @spec to_hex(trace_id :: t) :: String.t
  def to_hex(trace_id)
  def to_hex({id, _unique}) do
    Tapper.Id.Utils.to_hex(id)
  end

  @doc "parse a trace id from a hex string, for propagation etc."
  @spec parse(String.t) :: {:ok, t} | :error
  def parse(s) do
    case Integer.parse(s, 16) do
      :error -> :error
      {integer, remaining} when byte_size(remaining) == 0 -> {:ok, {integer, uniq()}}
      _ -> :error
    end
  end

  defp uniq(), do: System.unique_integer([:monotonic, :positive])
end

defmodule Tapper.SpanId do
  @moduledoc """
  Generate, format or parse a span id.

  A span id is a 64-bit integer.
  """
  @type int64 :: integer()
  @type t :: int64()

  @doc "generate a span id"
  @spec generate() :: t
  def generate() do
    <<id :: size(64)>> = :crypto.strong_rand_bytes(8)
    id
  end

  @doc "format a span id for logs etc."
  @spec format(span_id :: t) :: String.t
  def format(span_id) do
    "#Tapper.SpanId<" <> Tapper.Id.Utils.to_hex(span_id) <> ">"
  end

  @doc "format a span id as a hex string, for propagation etc."
  @spec to_hex(span_id :: t) :: String.t
  def to_hex(span_id) do
    Tapper.Id.Utils.to_hex(span_id)
  end

  @doc "parse a span id from a hex string, for propagation etc."
  @spec parse(String.t) :: {:ok, t} | :error
  def parse(s) do
    case Integer.parse(s, 16) do
      :error -> :error
      {integer, remaining} when byte_size(remaining) == 0 -> {:ok, integer}
      _ -> :error
    end
  end
end

defmodule Tapper.Id.Utils do
  @moduledoc false

  @doc "Lower-case base-16 conversion"
  def to_hex(val) when is_integer(val) do
    val
    |> Integer.to_string(16)
    |> String.downcase
  end

end
