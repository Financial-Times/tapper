defmodule Tapper.Tracer.Api do
  @moduledoc "The (minimal) API for the `Tapper.Tracer`; clients will normally use the `Tapper` module."

    @type trace_init :: {Tapper.TraceId.t, Tapper.SpanId.t, Tapper.SpanId.t | :root, boolean(), boolean()}

    @callback start(opts :: Keyword.t) :: Tapper.Id.t
    @callback join(trace_id :: Tapper.TraceId.t,
      span_id :: Tapper.SpanId.t,
      parent_id :: Tapper.SpanId.t | :root,
      sample :: boolean(), debug :: boolean(),
      opts :: Keyword.t) :: Tapper.Id.t
    @callback join(trace_init(), opts :: Keyword.t) :: Tapper.Id.t

    @callback start_span(tapper_id :: Tapper.Id.t, opts :: Keyword.t) :: Tapper.Id.t
    @callback finish_span(tapper_id :: Tapper.Id.t) :: Tapper.Id.t

    @callback finish(tapper_id :: Tapper.Id.t) :: :ok

    @callback annotate(tapper_id :: Tapper.Id.t, type :: atom(), opts :: Keyword.t) :: Tapper.Id.t

    @type binary_annotation_type :: :string | :bool | :i16 | :i32 | :i64 | :double | :bytes

    @callback binary_annotate(tapper_id :: Tapper.Id.t, type :: binary_annotation_type(), key :: String.t | atom(), value :: any(), endpoint :: Tapper.Endpoint.t | nil) :: Tapper.Id.t
end
