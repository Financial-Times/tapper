defmodule Tapper.Tracer.Api do
    @type trace_init :: {Tapper.TraceId.t, Tapper.SpanId.t, Tapper.SpanId.t | nil, boolean() | nil, boolean()}

    @callback start(opts :: Keyword.t) :: Tapper.Id.t
    @callback join(trace_init(), opts :: Keyword.t) :: Tapper.Id.t

    @callback start_span(tapper_id :: Tapper.Id.t, opts :: Keyword.t) :: Tapper.Id.t
    @callback finish_span(tapper_id :: Tapper.Id.t, opts :: Keyword.t) :: Tapper.Id.t

    @callback finish(tapper_id :: Tapper.Id.t) :: :ok

    # @callback annotate(tapper_id :: Tapper.Id.t, %Tapper.Span.Annotation{}) :: :ok
    # @callback binary_annotate(tapper_id :: Tapper.Id.t, %Tapper.Span.BinaryAnnotation{}) :: :ok
end
