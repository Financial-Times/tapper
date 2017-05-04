defmodule Tapper.Id do
  @moduledoc "The ID used with the API; tracks nested spans. Consider opaque!"

  defstruct [
    trace_id: nil,
    span_id: nil,
    origin_parent_id: :root, # root span from incoming trace, or :root
    parent_ids: [],          # stack of child spans
    sample: false,           # incoming trace sampled flag, or sample decision
    debug: false,            # incoming trace debug flag, or debug option
    sampled: false           # i.e. sample || debug
  ]

  @type t :: %__MODULE__{trace_id: Tapper.TraceId.t, span_id: Tapper.SpanId.t, parent_ids: [Tapper.SpanId.t], sampled: boolean(), origin_parent_id: Tapper.SpanId.t | :root, sample: boolean(), debug: boolean()} | :ignore

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

  @doc "Destructure the id, for trace propagation purposes."
  def destructure(%Tapper.Id{trace_id: {trace_id, _}, span_id: span_id, origin_parent_id: origin_parent_id, parent_ids: [], sample: sample, debug: debug}) do
    {trace_id, span_id, origin_parent_id, sample, debug}
  end
  def destructure(%Tapper.Id{trace_id: {trace_id, _}, span_id: span_id, origin_parent_id: origin_parent_id, parent_ids: [parent_id | _rest], sample: sample, debug: debug}) do
    {trace_id, span_id, parent_id, sample, debug}
  end

  defimpl Inspect do
    import Inspect.Algebra
    def inspect(id, _opts) do
      sampled = if(id.sampled, do: "SAMPLED", else: "-")
      concat ["#Tapper.Id<", Tapper.TraceId.format(id.trace_id), ":", Tapper.SpanId.format(id.span_id), ",", sampled, ">"]
    end
  end

  defimpl String.Chars do
    def to_string(id) do
      sampled = if(id.sampled, do: "SAMPLED", else: "-")
      "#Tapper.Id<" <> Tapper.TraceId.format(id.trace_id) <> ":" <> Tapper.SpanId.format(id.span_id) <> "," <> sampled <> ">"
    end
  end

end

defmodule Tapper.TraceId do
  @moduledoc """
  Generate, parse or format a top-level trace id.

  The TraceId comprises the 128-bit Zipkin id, with a second component which is a per-VM unique key,
  to disambiguate parallel requests to the same server, so each request gets it's own trace server,
  which prevents lifecycle confusion.
  """
  @type int128 :: integer()

  @type t :: {int128, integer()}

  @spec generate() :: t
  def generate() do
    <<id :: size(128)>> = :crypto.strong_rand_bytes(16)
    {id, uniq()}
  end

  def format({id, unique}) do
    "#Tapper.TraceId<" <> Tapper.Id.Utils.to_hex(id) <> "." <> Integer.to_string(unique) <> ">"
  end

  def to_hex({id, _unique}) do
    Tapper.Id.Utils.to_hex(id)
  end

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

  @spec generate() :: integer()
  def generate() do
    <<id :: size(64)>> = :crypto.strong_rand_bytes(8)
    id
  end

  def format(span_id) do
    "#Tapper.SpanId<" <> Tapper.Id.Utils.to_hex(span_id) <> ">"
  end

  def to_hex(span_id) do
    Tapper.Id.Utils.to_hex(span_id)
  end

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
