defmodule Tapper.Id do
    defstruct [
        trace_id: nil,
        span_id: nil,
        parent_ids: [],
        sampled: false
    ]

    @type t :: %__MODULE__{}

    @spec push(Tapper.Id.t, Tapper.SpanId.t) :: Tapper.Id.t
    def push(zid, span_id) do
        %Tapper.Id{zid | parent_ids: [zid.span_id | zid.parent_ids], span_id: span_id}
    end

    @spec pop(Tapper.Id.t) :: Tapper.Id.t
    def pop(zid = %Tapper.Id{parent_ids: [parent_id | parent_ids]}) do
        %Tapper.Id{zid | parent_ids: parent_ids, span_id: parent_id}
    end

    def pop(id = %Tapper.Id{parent_ids: []}), do: id

    defimpl Inspect do
        import Inspect.Algebra
        def inspect(id, _opts) do
            {hi, lo, _unique} = id.trace_id
            concat ["#Tapper.Id<", Integer.to_string(hi, 16), ",", Integer.to_string(lo, 16), ">"]
        end
    end

    defimpl String.Chars do
        import Inspect.Algebra
        def to_string(id) do
            {hi, lo, _unique} = id.trace_id
            "#Tapper.Id<" <> Integer.to_string(hi, 16) <> "," <> Integer.to_string(lo, 16) <> ">"
        end
    end
end


defmodule Tapper.TraceId do
    @moduledoc """
    Generate, or parse a top-level trace id.

    The TraceId comprises the 128-bit Zipkin id (with 64-bit compatibility), split into two 64-bit segements,
    with a third component which is a per-VM unique key, to disabiguate parallel requests to the same
    server, so each request gets it's own trace server, which prevents lifecycle confusion.
    """
    @type int64 :: integer()

    @type t :: {int64,int64,integer()} | {nil, int64, integer()}

    @spec generate() :: t
    def generate() do
        <<hi :: size(64), lo :: size(64)>> = :crypto.strong_rand_bytes(16)
        uniq = System.unique_integer([:monotonic])
        {hi,lo,uniq}
    end

    def format({hi, lo, unique}) do
        "#Tapper.TraceId<" <> Integer.to_string(hi, 16) <> "," <> Integer.to_string(lo, 16) <> "." <> Integer.to_string(unique) <> ">"
    end
end

defmodule Tapper.SpanId do
    @moduledoc """
    Generate, or parse a span id.

    A span id is a 64-bit bitfield.
    """
    @type int64 :: integer()
    @type t :: int64()

    @spec generate() :: integer()
    def generate() do
        <<id :: size(64)>> = :crypto.strong_rand_bytes(8)
        id
    end

    def format(span_id) do
        "#Tapper.SpanId<" <> Integer.to_string(span_id, 16) <> ">"
    end
end
