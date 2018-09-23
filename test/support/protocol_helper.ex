defmodule Test.Helper.Protocol do
  @moduledoc false

  @spec protocol_span_by_name([%Tapper.Protocol.Span{}], String.t) :: %Tapper.Protocol.Span{} | nil
  def protocol_span_by_name(spans, name) do
      Enum.find(spans, fn(span) -> span.name === name end)
  end

  def protocol_annotation_by_value(%Tapper.Protocol.Span{annotations: annotations}, value), do: protocol_annotation_by_value(annotations, value)
  def protocol_annotation_by_value(annotations, value) do
      Enum.find(annotations, fn(%Tapper.Protocol.Annotation{value: an_value}) -> an_value === value end)
  end

  def protocol_binary_annotation_by_key(%Tapper.Protocol.Span{binary_annotations: annotations}, key), do: protocol_binary_annotation_by_key(annotations, key)
  def protocol_binary_annotation_by_key(annotations, key) when is_list(annotations) do
      Enum.find(annotations, fn(%Tapper.Protocol.BinaryAnnotation{key: an_key}) -> an_key === key end)
  end

end
