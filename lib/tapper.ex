defmodule Tapper do
  @moduledoc """
  Client API for Tapper.

  ## Example
  ```
  # start new trace (and span)
  id = Tapper.start(name: "main", type: :client, debug: true, annotations: [Tapper.tag("a", "b")])

  # or join an existing one
  # id = Trapper.join(trace_id, span_id, parent_id, sample, debug, name: "main")

  # start child span
  id = Tapper.start_span(id, name: "call-out", annotations: [
    Tapper.wire_send(),
    Tapper.http_path("/resource/1234")
  ])

  # do something
  ...

  # tag current span with some additional metadata, e.g. when available
  Tapper.update_span(id, [
    Tapper.tag("userId", 12)
  ])
  ...

  # end child span
  id = Tapper.finish_span(child_id, annotations: [
    Tapper.http_status(200)
  ])

  Tapper.finish(span_id) # end trace
  ```
  """

  @behaviour Tapper.Tracer.Api

  @binary_annotation_types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

  alias Tapper.Tracer

  @doc """
  start a new root trace, e.g. on originating a request, e.g.:

  ```
  id = Tapper.Tracer.start(name: "request resource", type: :client, remote: remote_endpoint)
  ```

  ### Options

  * `name` - the name of the span.
  * `sample` - boolean, whether to sample this trace or not.
  * `debug` - boolean, enabled debug.
  * `type` - the type of the span, i.e.. `:client`, `:server`; defaults to `:client`. See notes below.
  * `annotations` (list) - a list of annotations, specified by `Tapper.http_host/2` etc.
  * `remote` (`%Tapper.Endpoint{}`) - the remote Endpoint: automatically creates a "sa" (client) or "ca" (server) binary annotation on this span, see also `Tapper.server_address/1`.
  * `ttl` - how long this span should live before automatically finishing it
      (useful for long-running async operations); milliseconds (default 30,000 ms)
  * `endpoint` - sets the endpoint for the annotation created by `type`, defaults to one derived from Tapper configuration (see `Tapper.Application.start/2`).
  * `reporter` - override the configured reporter for this trace; useful for testing.

  #### Notes

  * If neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  * `type` determines the type of an automatically created `sr` (`:server`) or `cs` (`:client`) annotation, see also `Tapper.client_send/0` and `Tapper.server_receive/0`.
  """
  defdelegate start(opts \\ []), to: Tracer

  @doc """
  join an existing trace, e.g. server recieving an annotated request.
  ```
  id = Tapper.Tracer.join(trace_id, span_id, parent_id, sampled, debug, name: "receive request")
  ```
  NB Probably called by an integration (e.g. [`tapper_plug`](https://github.com/Financial-Times/tapper_plug)) with name, annotations etc.
  added in the service code, so the name is optional here, see `name/1`.

  ### Arguments

  * `trace_id` - the trace id, as `Tapper.TraceId.t`.
  * `span_id` - the current span id, as `Tapper.SpanId.t`.
  * `parent_span_id` - the parent span id, as `Tapper.SpanId.t` or `:root` if root trace.
  * `sample` is the incoming sampling status; `true` implies trace has been sampled, and
      down-stream spans should be sampled also, `false` that it will not be sampled,
      and down-stream spans should not be sampled either.
  * `debug` is the debugging flag, if `true` this turns sampling for this trace on, regardless of
      the value of `sampled`.

  ### Options
  * `name` (String) - name of span
  * `type` - the type of the span, i.e.. `:client`, `:server`; defaults to `:server`. See notes below.
  * `annotations` (list) - a list of annotations, specified by `Tapper.tag/3` etc.
  * `remote` (`Tapper.Endpoint`) - the remote endpoint: automatically creates a "sa" (`:client`) or "ca" (`:server`) binary annotation on this span, see also `Tapper.server_address/1`.
  * `ttl` (integer) - how long this span should live between operations before automatically finishing it (useful for long-running async operations);
      milliseconds, defaults to 30,000 ms.
  * `endpoint` - sets the endpoint for the initial `cr` or `sr` annotation, defaults to one derived from Tapper configuration (see `Tapper.Application.start/2`).
  * `reporter` - override the configured reporter for this trace; useful for testing.

  #### Notes

  * If neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  * `type` determines the type of an automatically created `sr` (`:server`) or `cs` (`:client`) annotation, see also `Tapper.client_send/0` and `Tapper.server_receive/0`.
  """
  defdelegate join(trace_id, span_id, parent_id, sample, debug, opts \\ []), to: Tracer

  @doc """
  Finishes the trace.

  For `async` processes (where spans persist in another process), call
  `finish/2` when done with the main span, passing the `async` option, and finish
  child spans as normal using `finish_span/2`. When the trace times out, spans will
  be sent to the server, marking any unfinished spans with a `timeout` annotation.

  ## Options
  * `async` - mark the trace as asynchronous, allowing child spans to finish within the TTL.
  * `annotations` (list) - a list of annotations to attach to the span.

  ## See also
  * `Tapper.Tracer.Timeout` - timeout behaviour.
  * `async/0` annotation.
  """
  defdelegate finish(id, opts \\ []), to: Tracer

  @doc """
  Starts a child span, returning an updated `Tapper.Id`.

  ## Arguments
  * `id` - Tapper id.

  ## Options
  * `name` (string) - name the span.
  * `local` (string) - provide a local span context name (via a `lc` binary annotation).
  * `annotations` (list) - a list of annotations to attach to the span.

  ```
  id = start_span(id, name: "foo", local: "do foo", annotations: [Tapper.sql_query("select * from foo")])
  ```
  """
  defdelegate start_span(id, opts \\ []), to: Tracer

  @doc """
  Finish a nested child span, returning an updated `Tapper.Id`.

  ## Arguments
  * `id` - Tapper id.

  ## Options
  * `annotations` (list) - a list of annotations to attach the the span.

  ```
  id = Tapper.finish_span(id, annotations: [Tapper.http_status_code(202)])
  ```
  """
  defdelegate finish_span(id, opts \\ []), to: Tracer

  @doc """
  Commit annotations to a span; returns the same `Tapper.Id`.

  Use with annotation helper functions:
  ```
  id = Tapper.start_span(id)

  Tapper.update_span(id, [
    Tapper.async(),
    Tapper.name("child"),
    Tapper.http_path("/server/x"),
    Tapper.tag("x", 101)
  ])
  ```
  """
  defdelegate update_span(id, deltas, opts \\[]), to: Tracer


  @doc "Annotation helper: name (or rename) the current span."
  def name(name), do: Tracer.name_delta(name)

  @doc """
  Annotation helper: marks the span as asynchronous, adding an `async` annotation.

  This is semantically equivalent to calling `finish/2` with the `async` option, and
  has the same time-out behaviour, but annotates individual spans as being asynchronous.
  You can call this for every asynchronous span.

  Ensure that child spans, and the whole trace, are finished as normal.

  ## See also
  * `Tapper.Tracer.Timeout`
  * `Tapper.finish/2`
  """
  def async, do: Tracer.async_delta()

  @doc "Annotation helper: mark a server_receive event (`sr` annotation); see also `:server` option on `Tapper.start/1`."
  def server_receive, do: Tracer.annotation_delta(:sr)

  @doc "Annotation helper: mark a server_send event (`ss` annotation)."
  def server_send, do: Tracer.annotation_delta(:ss)

  @doc "Annotation helper: mark a client_send event (`cs` annotation); see also `:client` option on `Tapper.start/1`."
  def client_send, do: Tracer.annotation_delta(:cs)

  @doc "Annotation helper: mark a client_receive event (`cr` annotation)."
  def client_receive, do: Tracer.annotation_delta(:cr)

  @doc "Annotation helper: mark a send event (`ws` annotation)."
  def wire_send, do: Tracer.annotation_delta(:ws)

  @doc "Annotation helper: mark a receive event (`wr` annotation)."
  def wire_receive, do: Tracer.annotation_delta(:wr)

  @doc "Annotation helper: mark an error event (`error` annotation)."
  def error, do: Tracer.annotation_delta(:error)

  @doc "Annotation helper: Tag with the client's address (`ca` binary annotation)."
  def client_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :ca, true, endpoint)

  @doc "Annotation helper: Tag with the server's address (`sa` binary annotation)."
  def server_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :sa, true, endpoint)

  @doc "Annotation helper: Tag with HTTP host information (`http.host` binary annotation)."
  def http_host(hostname) when is_binary(hostname), do: Tracer.binary_annotation_delta(:string, "http.host", hostname)

  @doc "Annotation helper: Tag with HTTP method information (`http.method` binary annotation)."
  def http_method(method) when is_binary(method) or is_atom(method), do: Tracer.binary_annotation_delta(:string, "http.method", method)

  @doc "Annotation helper: Tag with HTTP path information: should be without query parameters (`http.path` binary annotation)"
  def http_path(path) when is_binary(path), do: Tracer.binary_annotation_delta(:string, "http.path", path)

  @doc "Annotation helper: Tag with full HTTP URL information (`http.url` binary annotation)"
  def http_url(url) when is_binary(url), do: Tracer.binary_annotation_delta(:string, "http.url", url)

  @doc "Annotation helper: Tag with an HTTP status code (`http.status_code` binary annotation)"
  def http_status_code(code) when is_integer(code), do: Tracer.binary_annotation_delta(:i16, "http.status_code", code)

  @doc "Annotation helper: Tag with an HTTP request size (`http.request.size` binary annotation)"
  def http_request_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.request.size", size)

  @doc "Annotation helper: Tag with an HTTP reponse size (`http.response.size` binary annotation)"
  def http_response_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.response.size", size)

  @doc "Annotation helper: Tag with a database query (`sql.query` binary annotation)"
  def sql_query(query) when is_binary(query), do: Tracer.binary_annotation_delta(:string, "sql.query", query)

  @doc "Annotation helper: Tag with an error message (`error` binary annotation)"
  def error_message(message) when is_binary(message), do: Tracer.binary_annotation_delta(:string, :error, message)

  @doc "Annotation helper: Tag with a general (key,value,host) binary annotation, determining type of annotation automatically"
  def tag(key, value, endpoint \\ nil)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_binary(value), do: Tracer.binary_annotation_delta(:string, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_boolean(value), do: Tracer.binary_annotation_delta(:bool, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_integer(value), do: Tracer.binary_annotation_delta(:i64, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_float(value), do: Tracer.binary_annotation_delta(:double, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)), do: Tracer.binary_annotation_delta(:string, key, inspect(value), endpoint)

  @doc "Annotation helper: mark an event (annotation), general interface."
  def annotation(value, endpoint \\ nil) when not is_map(value), do: Tracer.annotation_delta(value, endpoint)

  @doc """
  Annotation helper: tag with a general binary annotation.

  ```
  binary_annotation(id, :i16, "tab", 4)
  ```
  """
  def binary_annotation(type, key, value, endpoint \\ nil) when type in @binary_annotation_types do
     Tracer.binary_annotation_delta(type, key, value, endpoint)
  end

end
