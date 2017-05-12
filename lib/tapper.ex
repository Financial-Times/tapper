defmodule Tapper do
  @moduledoc """
  Client API for Tapper.

  ## Example
  ```
  id = Tapper.start(name: "main", type: :client, debug: true) # start new trace (and span)

  # or join an existing one
  # id = Trapper.join(trace_id, span_id, parent_id, sample, debug, name: "main")

  id = Tapper.start_span(id, name: "call-out") # start child span

  # tag current span with metadata
  id
  |> Tapper.http_path("/resource/1234")
  |> Tapper.tag("version", 12)

  ...
  id = Tapper.finish_span(child_id) # end child span

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

  Options:

  * `name` - the name of the span.
  * `sample` - boolean, whether to sample this trace or not.
  * `debug` - boolean, enabled debug.
  * `type` - the type of the span, i.e.. `:client`, `:server`; defaults to `:client`.
  * `remote` ([`%Tapper.Endpoint{}`](Tapper.Endpoint.html)) - the remote Endpoint: automatically creates a "sa" (client) or "ca" (server) binary annotation on this span.
  * `ttl` - how long this span should live before automatically finishing it
      (useful for long-running async operations); milliseconds (default 30,000 ms)
  * `endpoint` - sets the endpoint for the initial `cr` or `sr` annotation, defaults to one derived from Tapper configuration (see `Tapper.Application.start/2`).
  * `reporter` - override the configured reporter for this trace; useful for testing.

  NB if neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  """
  defdelegate start(opts \\ []), to: Tracer

  @doc """
  join an existing trace, e.g. server recieving an annotated request.
  ```
  id = Tapper.Tracer.join(trace_id, span_id, parent_id, sampled, debug, name: "receive request")
  ```
  NB Probably called by an integration (e.g. [`tapper_plug`](https://github.com/Financial-Times/tapper_plug), name, annotations etc.
  added in the service code, so the name is optional here, see `name/2`.

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
  * `type` (atom) - the type of the span, i.e.. :client, :server; defaults to `:server`.
  * `remote` (`Tapper.Endpoint`) - the remote endpoint: automatically creates a "sa" (`:client`) or "ca" (`:server`) binary annotation on this span.
  * `ttl` (integer) - how long this span should live between operations before automatically finishing it (useful for long-running async operations);
      milliseconds, defaults to 30,000 ms.
  * `endpoint` - sets the endpoint for the initial `cr` or `sr` annotation, defaults to one derived from Tapper configuration (see `Tapper.Application.start/2`).
  * `reporter` - override the configured reporter for this trace; useful for testing.

  NB if neither `sample` nor `debug` are `true`, all operations on this trace become a no-op.
  """
  defdelegate join(trace_id, span_id, parent_id, sample, debug, opts \\ []), to: Tracer

  @doc """
  Finishes the trace.

  For `async` processes (where spans persist in another process), call
  `finish/2` when done with the main span, passing the `async` option, and finish
  child spans as normal using `finish_span/1`. When the trace times out, spans will
  be sent to the server, marking any unfinished spans with a `timeout` annotation.

  ## Options
  * `async` - mark the trace as asynchronous, allowing child spans to finish within the TTL.

  ## See also
  * `Tapper.Tracer.Timeout`
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

  @doc "finish a nested span, returning an updated `Tapper.Id`."
  defdelegate finish_span(id), to: Tracer

  @doc "name (or rename) the current span."
  def name(id, name), do: Tracer.update_span(id, [name(name)])

  @doc "delta: name (or rename) the current span."
  def name(name), do: Tracer.name_delta(name)

  @doc """
  Marks the span as asynchronous, adding an `async` annotation.

  This is semantically equivalent to calling `finish/2` with the `async` option, and engages
  has the same time-out behaviour, but annotates individual spans as being asynchronous.
  You can call this for every asynchronous span.

  Ensure that child spans, and the whole trace, are finished as normal.

  ## See also
  * `Tapper.Tracer.Timeout`
  """
  def async(id), do: Tracer.update_span(id, [async()])

  @doc "delta: marks the span as asynchronous, adding an `async annotation."
  def async, do: Tracer.async_delta()

  @doc "mark a server_receive event (`sr`); see also `:server` option on `Tapper.start/1`."
  def server_receive(id = %Tapper.Id{}), do: Tracer.update_span(id, [server_receive()])
  def server_receive, do: Tracer.annotation_delta(:sr)

  @doc "mark a server_send event (`ss`)."
  def server_send(id = %Tapper.Id{}), do: Tracer.update_span(id, [server_send()])
  def server_send, do: Tracer.annotation_delta(:ss)

  @doc "mark a client_send event (`cs`); see also `:client` option on `Tapper.start/1`."
  def client_send(id), do: Tracer.update_span(id, [client_send()])
  def client_send, do: Tracer.annotation_delta(:cs)

  @doc "mark a client_receive event (`cr`)."
  def client_receive(id), do: Tracer.update_span(id, [client_receive()])
  def client_receive, do: Tracer.annotation_delta(:cr)

  @doc "mark a send event (`ws`)."
  def wire_send(id), do: Tracer.update_span(id, [wire_send()])
  def wire_send, do: Tracer.annotation_delta(:ws)

  @doc "mark a receive event (`wr`)."
  def wire_receive(id), do: Tracer.update_span(id, [wire_receive()])
  def wire_receive, do: Tracer.annotation_delta(:wr)

  @doc "mark an error event (`error` annotation)."
  def error(id), do: Tracer.update_span(id, [error()])
  def error, do: Tracer.annotation_delta(:error)

  @doc "Tag with the client's address (`ca`)."
  def client_address(id, endpoint = %Tapper.Endpoint{}), do: Tracer.update_span(id, [client_address(endpoint)])
  def client_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :ca, true, endpoint)

  @doc "Tag with the server's address (`sa`)."
  def server_address(id, endpoint = %Tapper.Endpoint{}), do: Tracer.update_span(id, [server_address(endpoint)])
  def server_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :sa, true, endpoint)

  @doc "Tag with HTTP host information (`http.host`)."
  def http_host(id, hostname) when is_binary(hostname), do: Tracer.update_span(id, [http_host(hostname)])
  def http_host(hostname) when is_binary(hostname), do: Tracer.binary_annotation_delta(:string, "http.host", hostname)

  @doc "Tag with HTTP method information (`http.method`)."
  def http_method(id, method) when is_binary(method) or is_atom(method), do: Tracer.update_span(id, [http_method(method)])
  def http_method(method) when is_binary(method) or is_atom(method), do: Tracer.binary_annotation_delta(:string, "http.method", method)

  @doc "Tag with HTTP path information: should be without query parameters (`http.path`)"
  def http_path(id, path) when is_binary(path), do: Tracer.update_span(id, [http_path(path)])
  def http_path(path) when is_binary(path), do: Tracer.binary_annotation_delta(:string, "http.path", path)

  @doc "Tag with full HTTP URL information (`http.url`)"
  def http_url(id, url) when is_binary(url), do: Tracer.update_span(id, [http_url(url)])
  def http_url(url) when is_binary(url), do: Tracer.binary_annotation_delta(:string, "http.url", url)

  @doc "Tag with an HTTP status code (`http.status_code`)"
  def http_status_code(id, code) when is_integer(code), do: Tracer.update_span(id, [http_status_code(code)])
  def http_status_code(code) when is_integer(code), do: Tracer.binary_annotation_delta(:i16, "http.status_code", code)

  @doc "Tag with an HTTP request size (`http.request.size`)"
  def http_request_size(id, size) when is_integer(size), do: Tracer.update_span(id, [http_request_size(size)])
  def http_request_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.request.size", size)

  @doc "Tag with an HTTP reponse size (`http.response.size`)"
  def http_response_size(id, size) when is_integer(size), do: Tracer.update_span(id, [http_response_size(size)])
  def http_response_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.response.size", size)

  @doc "Tag with a database query (`sql.querl`)"
  def sql_query(id, query) when is_binary(query), do: Tracer.update_span(id, [sql_query(query)])
  def sql_query(query) when is_binary(query), do: Tracer.binary_annotation_delta(:string, "sql.query", query)

  @doc "Tag with an error message (`error` binary annotation)"
  def error_message(id = %Tapper.Id{}, message) when is_binary(message), do: Tracer.update_span(id, [error_message(message)])
  def error_message(message) when is_binary(message), do: Tracer.binary_annotation_delta(:string, :error, message)

  @doc "Tag with a general (key,value,host) binary annotation, determining type of annotation automatically"
  def add_tag(id, key, value, endpoint \\ nil), do: Tracer.update_span(id, [tag(key, value, endpoint)])

  def tag(key, value, endpoint \\ nil)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_binary(value), do: Tracer.binary_annotation_delta(:string, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_boolean(value), do: Tracer.binary_annotation_delta(:bool, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_integer(value), do: Tracer.binary_annotation_delta(:i64, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_float(value), do: Tracer.binary_annotation_delta(:double, key, value, endpoint)
  def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)), do: Tracer.binary_annotation_delta(:string, key, inspect(value), endpoint)

  @doc "mark an event, general interface."
  def add_annotation(id, value, endpoint \\ nil) when is_map(id), do: Tracer.update_span(id, [annotate(value, endpoint)])
  def annotate(value, endpoint \\ nil) when not is_map(value), do: Tracer.annotation_delta(value, endpoint)

  @doc """
  Tag with a general binary annotation.

  ```
  binary_annotation(id, :i16, "tab", 4)
  ```
  """
  def add_binary_annotation(id, type, key, value, endpoint \\ nil), do: Tracer.update_span(id, [binary_annotate(type, key, value, endpoint)])

  def binary_annotate(type, key, value, endpoint \\ nil) when type in @binary_annotation_types do
     Tracer.binary_annotation_delta(type, key, value, endpoint)
  end

  defdelegate update_span(id, deltas, opts), to: Tracer

end
