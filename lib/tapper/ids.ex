defmodule Tapper.Id.Utils do

    def to_hex(val) when is_integer(val) do
        val
        |> Integer.to_string(16)
        |> String.downcase
    end

end

defmodule Tapper.Id do
    defstruct [
        trace_id: nil,
        span_id: nil, 
        parent_ids: [],
        sampled: false
    ]

    @type t :: %__MODULE__{trace_id: Tapper.TraceId.t, span_id: Tapper.SpanId.t, parent_ids: [Tapper.SpanId.t], sampled: boolean()}

    @spec push(Tapper.Id.t, Tapper.SpanId.t) :: Tapper.Id.t
    def push(id, span_id) do
        %Tapper.Id{id | parent_ids: [id.span_id | id.parent_ids], span_id: span_id}
    end

    @spec pop(Tapper.Id.t) :: Tapper.Id.t
    def pop(id = %Tapper.Id{parent_ids: []}), do: id
    def pop(id = %Tapper.Id{parent_ids: [parent_id | parent_ids]}) do
        %Tapper.Id{id | parent_ids: parent_ids, span_id: parent_id}
    end

    defimpl Inspect do
        import Inspect.Algebra
        def inspect(id, _opts) do
            
            concat ["#Tapper.Id<", Tapper.TraceId.format(id.trace_id), ":", Tapper.SpanId.format(id.span_id), ">"]
        end
    end

    defimpl String.Chars do
        import Inspect.Algebra
        def to_string(id) do
            "#Tapper.Id<" <> Tapper.TraceId.format(id.trace_id) <> ":" <> Tapper.SpanId.format(id.span_id) <> ">"
        end
    end

end

defmodule Tapper.TraceId do
    @moduledoc """
    Generate, or format a top-level trace id.

    The TraceId comprises the 128-bit Zipkin id (with 64-bit compatibility),
    with a second component which is a per-VM unique key, to disabiguate parallel requests to the same
    server, so each request gets it's own trace server, which prevents lifecycle confusion.
    """
    @type int128 :: integer()

    @type t :: {int128,integer()}

    @spec generate() :: t
    def generate() do
        <<id :: size(128)>> = :crypto.strong_rand_bytes(16)
        uniq = System.unique_integer([:monotonic, :positive])
        {id,uniq}
    end

    def format({id, unique}) do
        "#Tapper.TraceId<" <> Tapper.Id.Utils.to_hex(id) <> "." <> Integer.to_string(unique) <> ">"
    end

    def to_hex({id, _unique}) do
        Tapper.Id.Utils.to_hex(id)
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
        "#Tapper.SpanId<" <> Tapper.Id.Utils.to_hex(span_id) <> ">"
    end

    def to_hex(span_id) do
        Tapper.Id.Utils.to_hex(span_id)
    end
end
