defmodule TraceIdTest do
  use ExUnit.Case
  doctest Tapper.TraceId

  test "can generate id" do
    {hi, lo, uniq} = Tapper.TraceId.generate()
    assert is_integer(hi)
    assert is_integer(lo)
    assert is_integer(uniq)
  end

  test "format" do
    assert Tapper.TraceId.format({100,200,300}) == "#Tapper.TraceId<000000000000006400000000000000C8.300>"
  end
end

defmodule SpanIdTest do
  use ExUnit.Case
  doctest Tapper.SpanId

  test "can generate id" do
    span_id = Tapper.SpanId.generate()
    assert is_integer(span_id)
  end

  test "format" do
    assert Tapper.SpanId.format(1024) == "#Tapper.SpanId<0000000000000400>"
  end
end

defmodule TapperIdTest do
  use ExUnit.Case

  test "push span when empty" do
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: []
    }

    span_id = Tapper.SpanId.generate()

    updated_id = Tapper.Id.push(id, span_id)

    assert updated_id.parent_ids == [id.span_id]
    assert updated_id.span_id == span_id
  end

  test "push span when has parents" do
    parent_span_id = Tapper.SpanId.generate()

    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: [parent_span_id]
    }

    span_id = Tapper.SpanId.generate()

    updated_id = Tapper.Id.push(id, span_id)

    assert updated_id.parent_ids == [id.span_id, parent_span_id]
    assert updated_id.span_id == span_id
  end

  test "pop span, one parent" do
    parent_span_id = Tapper.SpanId.generate()
    
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: [parent_span_id]
    }

    updated_id = Tapper.Id.pop(id)

    assert updated_id.span_id == parent_span_id
    assert updated_id.parent_ids == []
  end

  test "pop span, more than one parent" do
    parent1_span_id = Tapper.SpanId.generate()
    parent2_span_id = Tapper.SpanId.generate()
    
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: [parent1_span_id, parent2_span_id]
    }

    updated_id = Tapper.Id.pop(id)

    assert updated_id.span_id == parent1_span_id
    assert updated_id.parent_ids == [parent2_span_id]
  end

  test "pop span, no parents is no-op" do
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: []
    }

    assert Tapper.Id.pop(id) == id
  end

  test "Inspect protocol" do
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: []
    }

    regex = ~r/#Tapper.Id<(.+),(.+):(.+)>/
    assert Regex.match?(regex,inspect(id))

    [_, hi, lo, span_id] = Regex.run(regex, inspect(id))

    {hi, ""} = Integer.parse(hi, 16)
    {lo, ""} = Integer.parse(lo, 16)
    {span_id, ""} = Integer.parse(span_id, 16)

    assert hi == elem(id.trace_id,0)
    assert lo == elem(id.trace_id,1)
    assert span_id == id.span_id
  end
  
  test "String.Chars protocol" do
    id = %Tapper.Id{
      trace_id: Tapper.TraceId.generate(),
      span_id: Tapper.SpanId.generate(),
      parent_ids: []
    }

    regex = ~r/#Tapper.Id<(.+),(.+):(.+)>/

    chars = to_string(id)

    assert Regex.match?(regex, chars)

    [_, hi, lo, span_id] = Regex.run(regex, chars)

    {hi, ""} = Integer.parse(hi, 16)
    {lo, ""} = Integer.parse(lo, 16)
    {span_id, ""} = Integer.parse(span_id, 16)

    assert hi == elem(id.trace_id,0)
    assert lo == elem(id.trace_id,1)
    assert span_id == id.span_id
  end
end