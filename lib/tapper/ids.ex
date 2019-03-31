defmodule Tapper.Id do
  @moduledoc """
  The ID used with the API; tracks nested spans.

  > Clients should consider this ID opaque!

  Use `destructure/1` to obtain trace parameters. NB special value `:ignore` produces no-ops in API functions.
  """

  require Logger

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

  @doc "Create id from trace context"
  @spec init(trace_id :: TraceId.t, span_id :: SpanId.t, parent_span_id :: SpanId.t | :root, sample :: boolean, debug :: boolean) :: t
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
    {trace_id, span_id, "", sample, debug}
  end
  def destructure(%Tapper.Id{trace_id: trace_id, span_id: span_id, origin_parent_id: origin_parent_id, parent_ids: [], sample: sample, debug: debug}) do
    {trace_id, span_id, origin_parent_id, sample, debug}
  end
  def destructure(%Tapper.Id{trace_id: trace_id, span_id: span_id, origin_parent_id: _origin_parent_id, parent_ids: [parent_id | _rest], sample: sample, debug: debug}) do
    {trace_id, span_id, parent_id, sample, debug}
  end

  @doc "Generate a TraceId for testing; sample is true"
  def test_id(parent_span_id \\ :root) do
    trace_id = <<span_id :: bytes-size(16), _rest::bits>> = Tapper.TraceId.generate()
    %Tapper.Id{
      trace_id: trace_id,
      span_id: span_id,
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
      sampled = if(id.sampled, do: "SAMPLED", else: "-")
      "#Tapper.Id<" <> Tapper.TraceId.format(id.trace_id) <> ":" <> Tapper.SpanId.format(id.span_id) <> "," <> sampled <> ">"
    end
  end

end

defmodule Tapper.Id.HexConversion do
  @moduledoc false

  @doc "Lower-case base-16 conversion"
  defmacro gen_inline_hex() do
    for val <- 0..255 do
      b = <<val::8>>
      h = Base.encode16(b, case: :lower)
      quote do
        defp hex(unquote(val)), do: unquote(h)
      end
    end
  end
end


defmodule Tapper.TraceId do
  @moduledoc """
  Generate, parse or format a top-level trace id.

  The TraceId comprises 128-bits encoded as a lower-case hex string.
  """
  @type t :: binary()

  defstruct [:value]   # NB only used as wrapper for e.g. logging format

  require Tapper.Id.HexConversion
  Tapper.Id.HexConversion.gen_inline_hex()

  @doc "generate a trace id"
  @spec generate() :: t
  def generate() do
    <<c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, _ :: bits>> = :crypto.strong_rand_bytes(16)
    <<
      hex(c1)::bytes-size(2),
      hex(c2)::bytes-size(2),
      hex(c3)::bytes-size(2),
      hex(c4)::bytes-size(2),
      hex(c5)::bytes-size(2),
      hex(c6)::bytes-size(2),
      hex(c7)::bytes-size(2),
      hex(c8)::bytes-size(2),
      hex(c9)::bytes-size(2),
      hex(c10)::bytes-size(2),
      hex(c11)::bytes-size(2),
      hex(c12)::bytes-size(2),
      hex(c13)::bytes-size(2),
      hex(c14)::bytes-size(2),
      hex(c15)::bytes-size(2),
      hex(c16)::bytes-size(2)
  >>
  end

  @doc "format a trace id for logs etc."
  @spec format(trace_id :: t) :: String.t
  def format(trace_id)
  def format(trace_id) do
    "#Tapper.TraceId<" <> trace_id <> ">"
  end

  @doc "format a trace id to a hex string, for propagation etc."
  @spec to_hex(trace_id :: t) :: String.t
  def to_hex(trace_id), do: trace_id

  @doc "parse a trace id from a hex string, for propagation etc."
  def parse(<<trace_id::bytes-size(32)>>) do
    if valid_lower_case_hex?(trace_id, 32) do
      {:ok, trace_id}
    else
      :error
    end
  end
  def parse(<<trace_id::bytes-size(16)>>) do
    if valid_lower_case_hex?(trace_id, 16) do
      {:ok, trace_id}
    else
      :error
    end
  end
  def parse(_), do: :error

  defp valid_lower_case_hex?(b, expected_digits) do
    count_digits(b, 0) === expected_digits
  end

  for chars <- [?0..?9, ?a..?f],
      char <- chars do

    defp count_digits(<<unquote(char), rest::bits>>, count) do
      count_digits(rest, count + 1)
    end
  end

  defp count_digits(_, count), do: count

  defimpl Inspect do
    import Inspect.Algebra
    @doc false
    def inspect(trace_id, _opts) do
      concat [Tapper.TraceId.format(trace_id.value)]
    end
  end

  defimpl String.Chars do
    @doc false
    def to_string(trace_id) do
      trace_id.value
    end
  end

end

defmodule Tapper.SpanId do
  @moduledoc """
  Generate, format or parse a span id.

  The SpanId comprises 64-bits encoded as a lower-case hex string.
  """
  @type t :: binary()

  require Tapper.Id.HexConversion
  Tapper.Id.HexConversion.gen_inline_hex()

  @doc "generate a span id"
  @spec generate() :: t
  def generate() do
    <<c1, c2, c3, c4, c5, c6, c7, c8, _ :: bits>> = :crypto.strong_rand_bytes(8)
    <<
      hex(c1)::bytes-size(2),
      hex(c2)::bytes-size(2),
      hex(c3)::bytes-size(2),
      hex(c4)::bytes-size(2),
      hex(c5)::bytes-size(2),
      hex(c6)::bytes-size(2),
      hex(c7)::bytes-size(2),
      hex(c8)::bytes-size(2),
    >>
  end

  @doc "format a span id for logs etc."
  @spec format(span_id :: t) :: String.t
  def format(span_id) do
    "#Tapper.SpanId<" <> span_id <> ">"
  end

  @doc "format a span id as a hex string, for propagation etc."
  @spec to_hex(span_id :: t) :: String.t
  def to_hex(span_id) do
    span_id
  end

  @doc "parse a span id from a hex string, for propagation etc."
  @spec parse(String.t) :: {:ok, t} | :error
  def parse(<<span_id::bytes-size(16)>>) do
    if valid_lower_case_hex?(span_id) do
      {:ok, span_id}
    else
      :error
    end
  end
  def parse(_), do: :error

  defp valid_lower_case_hex?(b) do
    count_digits(b, 0) === 16
  end

  for chars <- [?0..?9, ?a..?f],
      char <- chars do

    defp count_digits(<<unquote(char), rest::bits>>, count) do
      count_digits(rest, count + 1)
    end
  end

  defp count_digits(_, count), do: count
end
