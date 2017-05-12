defmodule Tapper.Tracer.Api do
  @moduledoc "The (minimal) low-level API for the `Tapper.Tracer`; clients will normally use the `Tapper` module."
  alias Tapper.Endpoint

  @type maybe_endpoint :: Endpoint.t | nil

  @typedoc "Delta for span name"
  @type name_delta :: {:name, name :: String.t | atom()}

  @typedoc "Delta for async span"
  @type async_delta :: :async

  @type annotation_value :: String.t | atom()

  @typedoc "Delta for simple annotations"
  @type annotation_delta :: {
    :annotate,
    {value :: annotation_value(),  endpoint :: maybe_endpoint()}
  }

  @type binary_annotation_type :: :string | :bool | :i16 | :i32 | :i64 | :double | :bytes
  @type binary_annotation_key :: String.t | atom()
  @type binary_annotation_value :: String.t | atom() | boolean() | integer() | float() | binary()

  @typedoc "Delta for binary annotations"
  @type binary_annotation_delta :: {
    :binary_annotate,
    {
      type :: binary_annotation_type(),
      key :: binary_annotation_key(),
      value :: binary_annotation_value,
      endpoint :: maybe_endpoint()
    }
  }

  @type delta :: name_delta | async_delta | annotation_delta | binary_annotation_delta

  # operations
  @callback start(opts :: Keyword.t) :: Tapper.Id.t
  @callback join(trace_id :: Tapper.TraceId.t,
    span_id :: Tapper.SpanId.t,
    parent_id :: Tapper.SpanId.t | :root,
    sample :: boolean(), debug :: boolean(),
    opts :: Keyword.t) :: Tapper.Id.t

  @callback start_span(tapper_id :: Tapper.Id.t, opts :: Keyword.t) :: Tapper.Id.t
  @callback update_span(tapper_id :: Tapper.Id.t, deltas :: [delta], opts :: Keyword.t) :: Tapper.Id.t
  @callback finish_span(tapper_id :: Tapper.Id.t) :: Tapper.Id.t

  @callback finish(tapper_id :: Tapper.Id.t) :: :ok

end
