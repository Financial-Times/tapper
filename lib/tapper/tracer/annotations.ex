defmodule Tapper.Tracer.Annotations do
  @moduledoc "Helpers for creating annotations"

  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  @spec annotation(value :: atom() | String.t, timestamp :: Timestamp.timestamp(), Tapper.Endpoint.t) :: Trace.Annotation.t
  def annotation(value, timestamp, endpoint)
  def annotation(value, timestamp, endpoint = %Tapper.Endpoint{}) when is_atom(value) and is_tuple(timestamp) do
    Trace.Annotation.new(value, timestamp, endpoint)
  end

  @spec binary_annotation(type :: atom(), Tapper.Endpoint.t) :: Trace.BinaryAnnotation.t
  def binary_annotation(type, endpoint)
  def binary_annotation(:ca, endpoint = %Tapper.Endpoint{}), do: Trace.BinaryAnnotation.new(:ca, true, :bool, endpoint)
  def binary_annotation(:sa, endpoint = %Tapper.Endpoint{}), do: Trace.BinaryAnnotation.new(:sa, true, :bool, endpoint)


  @spec binary_annotation(type :: atom(), key :: String.t | atom(), value :: any(), Tapper.Endpoint.t) :: Trace.BinaryAnnotation.t | nil
  def binary_annotation(type, key, value, endpoint = %Tapper.Endpoint{}) when is_atom(type) and is_binary(key) do
    case type do
      type when type in [:bool, :string, :bytes, :i16, :i32, :i64, :double] ->
        Trace.BinaryAnnotation.new(key, value, type, endpoint)
      _ ->
        nil
    end
  end

end
