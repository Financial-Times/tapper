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
      sampled = if(id.sampled, do: "SAMPLED", else: "-")
      "#Tapper.Id<" <> Tapper.TraceId.format(id.trace_id) <> ":" <> Tapper.SpanId.format(id.span_id) <> "," <> sampled <> ">"
    end
  end

end

defmodule Tapper.Id.Utils do
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

  The TraceId comprises the 128-bit Zipkin id encoded as a lower-case hex string.
  """
  @type t :: binary()

  defstruct [:value]   # NB only used as wrapper for e.g. logging format

  import Bitwise, only: [<<<: 2]
  require Tapper.Id.Utils
  Tapper.Id.Utils.gen_inline_hex()

  @doc "generate a trace id"
  @spec generate() :: t
  def generate(), do: generate(:inline_hex)

  def generate(:'0_4_0') do
    <<id :: size(128)>> = :crypto.strong_rand_bytes(16)
    {id, uniq()}
  end

  def generate(:base_mod) do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  def generate(:inline_hex) do
    <<c1, c2, c3, c4, c5, c6, c7, c8, c9 ,c10, c11, c12, c13, c14, c15, c16>> = :crypto.strong_rand_bytes(16)
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

  def generate(:inline_hex_no_size) do
    <<c1, c2, c3, c4, c5, c6, c7, c8, c9 ,c10, c11, c12, c13, c14, c15, c16>> = :crypto.strong_rand_bytes(16)
    <<
      hex(c1)::bytes,
      hex(c2)::bytes,
      hex(c3)::bytes,
      hex(c4)::bytes,
      hex(c5)::bytes,
      hex(c6)::bytes,
      hex(c7)::bytes,
      hex(c8)::bytes,
      hex(c9)::bytes,
      hex(c10)::bytes,
      hex(c11)::bytes,
      hex(c12)::bytes,
      hex(c13)::bytes,
      hex(c14)::bytes,
      hex(c15)::bytes,
      hex(c16)::bytes
    >>
  end


  def generate(:inline_hex_bl) do
    l = :binary.bin_to_list(:crypto.strong_rand_bytes(16))
    :binary.list_to_bin(:lists.map(&hex/1, l))
  end

  def generate(:lookup_table) do
    <<c1, c2, c3, c4, c5, c6, c7, c8, c9 ,c10, c11, c12, c13, c14, c15, c16>> = :crypto.strong_rand_bytes(16)
    # t = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
    t = lookup_table()
    <<
      :binary.part(t, c1 <<< 1, 2)::binary-size(2),
      :binary.part(t, c2 <<< 1, 2)::binary-size(2),
      :binary.part(t, c3 <<< 1, 2)::binary-size(2),
      :binary.part(t, c4 <<< 1, 2)::binary-size(2),
      :binary.part(t, c5 <<< 1, 2)::binary-size(2),
      :binary.part(t, c6 <<< 1, 2)::binary-size(2),
      :binary.part(t, c7 <<< 1, 2)::binary-size(2),
      :binary.part(t, c8 <<< 1, 2)::binary-size(2),
      :binary.part(t, c9 <<< 1, 2)::binary-size(2),
      :binary.part(t, c10 <<< 1, 2)::binary-size(2),
      :binary.part(t, c11 <<< 1, 2)::binary-size(2),
      :binary.part(t, c12 <<< 1, 2)::binary-size(2),
      :binary.part(t, c13 <<< 1, 2)::binary-size(2),
      :binary.part(t, c14 <<< 1, 2)::binary-size(2),
      :binary.part(t, c15 <<< 1, 2)::binary-size(2),
      :binary.part(t, c16 <<< 1, 2)::binary-size(2)
    >>
  end

  def generate(:lookup_table_comprehension) do
    t = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
    # t = lookup_table()
    for <<c <- :crypto.strong_rand_bytes(16)>>, into: <<>>, do: :binary.part(t, c <<< 1, 2)
  end

  l = for i <- 0..255, into: <<>> do
    Base.encode16(<<i::8>>, case: :lower)
  end
  defp lookup_table(), do: unquote(l)
  defp uniq(), do: System.unique_integer([:monotonic, :positive])

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
  @spec parse(String.t) :: {:ok, t} | :error
  def parse(<<trace_id::bytes-size(32)>>) do
    case Integer.parse(trace_id, 16) do
      :error -> :error
      {_, remaining} when byte_size(remaining) == 0 -> {:ok, trace_id}
      _ -> :error
    end
  end
  def parse(<<trace_id::bytes-size(16)>>) do
    case Integer.parse(trace_id, 16) do
      :error -> :error
      {_, remaining} when byte_size(remaining) == 0 -> {:ok, trace_id}
      _ -> :error
    end
  end
  def parse(_), do: :error

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
      Tapper.TraceId.to_hex(trace_id.value)
    end
  end

end

defmodule Tapper.SpanId do
  @moduledoc """
  Generate, format or parse a span id.

  A span id is a 64-bit integer encoded as a lower-case hex string.
  """
  @type t :: binary()

  require Tapper.Id.Utils
  Tapper.Id.Utils.gen_inline_hex()

  @doc "generate a span id"
  @spec generate() :: t
  def generate() do
    <<c1, c2, c3, c4, c5, c6, c7, c8>> = :crypto.strong_rand_bytes(8)
    <<
      hex(c1)::bytes,
      hex(c2)::bytes,
      hex(c3)::bytes,
      hex(c4)::bytes,
      hex(c5)::bytes,
      hex(c6)::bytes,
      hex(c7)::bytes,
      hex(c8)::bytes,
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
    case Integer.parse(span_id, 16) do
      :error -> :error
      {_, remaining} when byte_size(remaining) == 0 -> {:ok, span_id}
      _ -> :error
    end
  end
  def parse(_), do: :error
end
