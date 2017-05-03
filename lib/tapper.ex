defmodule Tapper do
  @moduledoc """
  Client API for Tapper.

  ```
  id = Tapper.start(name: "name, type: :client, debug: true) # start new trace (and span)
  # or join an existing one
  id = Trapper.join(trace_id, span_id, parent_id, sample, debug, name: "name")

  id = Tapper.start_span(id, type: :cr) # start child span

  # tag current span with metadata
  id
  |> Tapper.http_path("/resource/1234")
  |> Tapper.tag("version", 12)

  ...
  id = Tapper.finish_span(child_id) # end child span

  Tapper.finish(span_id) # end trace
  ```
  """

  defmodule Endpoint do
    @moduledoc "endpoint description struct"
      defstruct [
        :ipv4,
        :port,
        :service_name,
        :ipv6
      ]

      @type t :: %__MODULE__{}
  end

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
        * `remote` (%Tapper.Endpoint{}) - the remote Endpoint: automatically creates a "sa" (client) or "ca" (server) binary annotation on this span.
        * `ttl` - how long this span should live before automatically finishing it
            (useful for long-running async operations); milliseconds (default 30,000 ms)

    NB if neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  """
  def start(opts \\ []), do: Tapper.Tracer.start(opts)

  @doc """
    join an existing trace, e.g. server recieving an annotated request.
    ```
    id = Tapper.Tracer.join(trace_id, span_id, parent_id, sampled, debug, name: "receive request")
    ```
    NB The id could be generated at the top level, and annotations, name etc. set
    deeper in the service code, so the name is optional here, see also `name/2`.

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
        * `remote` (%Tapper.Endpoint{}) - the remote Endpoint: automatically creates a "sa" (client) or "ca" (server) binary annotation on this span.
        * `ttl` (integer) - how long this span should live before automatically finishing it (useful for long-running async operations);
            milliseconds, defaults to 30,000 ms.

    NB if neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  """
  def join(trace_id, span_id, parent_id, sample, debug, opts \\ []), do: Tapper.Tracer.join(trace_id, span_id, parent_id, sample, debug, opts)

  @doc "finish a trace for this request."
  def finish(id, opts \\ []), do: Tapper.Tracer.finish(id, opts)

  @doc """
  start a nested span.

  ### Arguments
      * `id` - Tapper id
  ### Options
      * `local` (string) - provide a local span context name (via a "lc"" binary annotation)
  """
  def start_span(id, opts \\ []), do: Tapper.Tracer.start_span(id, opts)

  @doc "finish a nested span."
  def finish_span(id), do: Tapper.Tracer.finish_span(id)

  @doc "name (or rename) the current span"
  def name(id, name), do: Tapper.Tracer.name(id, name)

  @doc "mark a server_receive event; see also `:server` option on `Tapper.start/1`"
  def server_receive(id), do: Tapper.Tracer.annotate(id, :sr)
  @doc "mark a server_send event"
  def server_send(id), do: Tapper.Tracer.annotate(id, :ss)

  @doc "mark a client_send event; see also `:client` option on `Tapper.start/1`"
  def client_send(id), do: Tapper.Tracer.annotate(id, :cs)
  @doc "mark a client_receive event"
  def client_receive(id), do: Tapper.Tracer.annotate(id, :cr)

  @doc "mark a send event"
  def wire_send(id), do: Tapper.Tracer.annotate(id, :ws)
  @doc "mark a receive event"
  def wire_receive(id), do: Tapper.Tracer.annotate(id, :wr)

  @doc "mark an error event"
  def error(id), do: Tapper.Tracer.annotate(id, :error)

  @doc "mark an event, general interface"
  def annotate(id, type, endpoint \\ nil), do: Tapper.Tracer.annotate(id, type, endpoint: endpoint)


  @doc "Tag with the client's address"
  def client_address(id, host = %Tapper.Endpoint{}), do: Tapper.Tracer.binary_annotate(id, :bool, "ca", true, host)

  @doc "Tag with the server's address"
  def server_address(id, host = %Tapper.Endpoint{}), do: Tapper.Tracer.binary_annotate(id, :bool, "sa", true, host)

  @doc "Tag with HTTP host information."
  def http_host(id, hostname) when is_binary(hostname), do: Tapper.Tracer.binary_annotate(id, :string, "http.host", hostname)

  @doc "Tag with HTTP method information."
  def http_method(id, method) when is_binary(method), do: Tapper.Tracer.binary_annotate(id, :string, "http.method", method)

  @doc "Tag with HTTP path information (should be without query parameters)"
  def http_path(id, path) when is_binary(path), do: Tapper.Tracer.binary_annotate(id, :string, "http.path", path)

  @doc "Tag with HTTP URL information"
  def http_url(id, url) when is_binary(url), do: Tapper.Tracer.binary_annotate(id, :string, "http.url", url)

  @doc "Tag with an HTTP status code"
  def http_status_code(id, code) when is_integer(code), do: Tapper.Tracer.binary_annotate(id, :i16, "http.status_code", code)

  @doc "Tag with an HTTP request size"
  def http_request_size(id, size) when is_integer(size), do: Tapper.Tracer.binary_annotate(id, :i64, "http.request.size", size)

  @doc "Tag with an HTTP reponse size"
  def http_response_size(id, size) when is_integer(size), do: Tapper.Tracer.binary_annotate(id, :i64, "http.response.size", size)

  @doc "Tag with a database query"
  def sql_query(id, query) when is_binary(query), do: Tapper.Tracer.binary_annotate(id, :string, "sql.query", query)

  @doc "Tag with an error message"
  def error(id, message) when is_binary(message), do: Tapper.Tracer.binary_annotate(id, :string, :error, message)

  @doc "Tag with a general (key,value,host) binary annotation, determining type of annotation automatically"
  def tag(id, key, value, opts \\ [])
  def tag(id, key, value, opts) when is_binary(key) and is_binary(value), do: Tapper.Tracer.binary_annotate(id, :string, key, value, opts)
  def tag(id, key, value, opts) when is_binary(key) and is_integer(value), do: Tapper.Tracer.binary_annotate(id, :i64, key, value, opts)
  def tag(id, key, value, opts) when is_binary(key) and is_float(value), do: Tapper.Tracer.binary_annotate(id, :double, key, value, opts)
  def tag(id, key, value, opts) when is_binary(key), do: Tapper.Tracer.binary_annotate(id, :string, key, inspect(value), opts)


  @binary_annotation_types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

  @doc """
  Tag with a general binary annotation.

  ```
  binary_annotation(id, :i16, "tab", 4, host: remote)
  ```
  """
  def binary_annotation(id, type, key, value, opts \\ [])
  def binary_annotation(id, type, key, value, opts) when type in @binary_annotation_types, do: Tapper.Tracer.binary_annotate(id, type, key, value, opts)

end
