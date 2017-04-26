defmodule Tapper.Tracer.Annotations do

    alias Tapper.Tracer.Trace

    def annotation(value, timestamp, endpoint)
    def annotation(value, timestamp, endpoint = %Tapper.Endpoint{}) when is_atom(value) and is_integer(timestamp) do
        cond do
            value in [:cs,:cr,:ss,:sr,:ws,:wr,:csf,:crf,:ssf,:srf,:error] ->
                Trace.Annotation.new(value, timestamp, endpoint)
            true -> nil
        end
    end

    def binary_annotation(type, endpoint)
    def binary_annotation(:ca, endpoint = %Tapper.Endpoint{}), do: Trace.BinaryAnnotation.new(:ca, true, :bool, endpoint)
    def binary_annotation(:sa, endpoint = %Tapper.Endpoint{}), do: Trace.BinaryAnnotation.new(:sa, true, :bool, endpoint)
    def binary_annotation(type, key, value, endpoint = %Tapper.Endpoint{}) when is_atom(type) and is_binary(key) do
        cond do
            type in [:bool, :string, :bytes, :i16, :i32, :i64, :double] ->
                Trace.BinaryAnnotation.new(key, value, type, endpoint)
            true ->
                nil
        end
    end

end