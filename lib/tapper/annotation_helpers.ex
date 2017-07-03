defmodule Tapper.AnnotationHelpers do
  @moduledoc """
  Defines convenience functions for creating annotations, primarily
  for high-level api definitions such as the `Tapper` module.

  Include these functions into a module with `use`:

  ```
  defmodule MyModule do
    use Tapper.AnnotationHelpers

    def fun() do
      annotations = [client_receive(), tag("a", 100)]
      ...
    end
  end
  ```

  """

  defmacro __using__(_) do
    quote do

      alias Tapper.Tracer
      alias Tapper.Tracer.Api

      @binary_annotation_types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

      @doc "Annotation helper: name (or rename) the current span."
      @spec name(name :: String.t | atom) :: Api.name_delta
      def name(name), do: Tracer.name_delta(name)

      @doc """
      Annotation helper: mark the span as asynchronous, and add an `async` event annotation.

      Adding this annotation is semantically equivalent to calling `finish/2` with the `async` option, and
      instigates the same time-out behaviour.

      You would probably add one of these to every asynchronous span, so we know which spans were async.

      Ensure that child spans, and the whole trace, are finished as normal.

      ## Example
      ```
      # start a trace
      id = Tapper.start(name: "main")

      # spawn a task
      ref = Task.start(fn ->
        # start a child span in the task
        child_id = Tapper.start_span(id, "fetch", annotations: Tapper.async())
        res = do_something()
        {res, child_id}
      end)

      # finish the trace, this won't send the spans; note we don't need async: true
      # if Task has already called start_span(), but it might not have, so safer to do so!
      Tapper.finish(id, async: true)
      ...
      # await the result from our task
      {res, span_id} = Task.await(ref)
      send_result_to_queue_or_something(res)

      # finish the child span; will complete trace and send spans
      Tapper.finish_span(span_id)
      ```

      ## See also
      * `Tapper.Tracer.Timeout`
      * `Tapper.finish/2`
      """
      @spec async() :: Api.async_delta
      def async, do: Tracer.async_delta()

      @doc "Annotation helper: create a server_receive event (`sr` event annotation); see also `:server` option on `Tapper.start/1`."
      @spec server_receive() :: Api.annotation_delta
      def server_receive, do: Tracer.annotation_delta(:sr)

      @doc "Annotation helper: create a server_send event (`ss` event annotation)."
      @spec server_send() :: Api.annotation_delta
      def server_send, do: Tracer.annotation_delta(:ss)

      @doc "Annotation helper: create a client_send event (`cs` event annotation); see also `:client` option on `Tapper.start/1`."
      @spec client_send() :: Api.annotation_delta
      def client_send, do: Tracer.annotation_delta(:cs)

      @doc "Annotation helper: create a client_receive event (`cr` event annotation)."
      @spec client_receive() :: Api.annotation_delta
      def client_receive, do: Tracer.annotation_delta(:cr)

      @doc "Annotation helper: create a send event (`ws` event annotation)."
      @spec wire_send() :: Api.annotation_delta
      def wire_send, do: Tracer.annotation_delta(:ws)

      @doc "Annotation helper: create a receive event (`wr` event annotation)."
      @spec wire_receive() :: Api.annotation_delta
      def wire_receive, do: Tracer.annotation_delta(:wr)

      @doc "Annotation helper: create an error event (`error` event annotation)."
      @spec error() :: Api.annotation_delta
      def error, do: Tracer.annotation_delta(:error)

      @doc "Annotation helper: tag the client's address (`ca` binary annotation)."
      @spec client_address(endpoint :: Tapper.Endpoint.t) :: Api.binary_annotation_delta
      def client_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :ca, true, endpoint)

      @doc "Annotation helper: tag with the server's address (`sa` binary annotation)."
      @spec server_address(endpoint :: Tapper.Endpoint.t) :: Api.binary_annotation_delta
      def server_address(endpoint), do: Tracer.binary_annotation_delta(:bool, :sa, true, endpoint)

      @doc "Annotation helper: tag with HTTP host information (`http.host` binary annotation)."
      @spec http_host(hostname :: String.t) :: Api.binary_annotation_delta
      def http_host(hostname) when is_binary(hostname), do: Tracer.binary_annotation_delta(:string, "http.host", hostname)

      @doc "Annotation helper: tag with HTTP method information (`http.method` binary annotation)."
      @spec http_method(method :: String.t | atom) :: Api.binary_annotation_delta
      def http_method(method) when is_binary(method) or is_atom(method), do: Tracer.binary_annotation_delta(:string, "http.method", method)

      @doc "Annotation helper: tag with HTTP path information: should be without query parameters (`http.path` binary annotation)"
      @spec http_path(path :: String.t) :: Api.binary_annotation_delta
      def http_path(path) when is_binary(path), do: Tracer.binary_annotation_delta(:string, "http.path", path)

      @doc "Annotation helper: tag with full HTTP URL information (`http.url` binary annotation)"
      @spec http_url(url :: String.t) :: Api.binary_annotation_delta
      def http_url(url) when is_binary(url), do: Tracer.binary_annotation_delta(:string, "http.url", url)

      @doc "Annotation helper: tag with an HTTP status code (`http.status_code` binary annotation)"
      @spec http_status_code(code :: integer()) :: Api.binary_annotation_delta
      def http_status_code(code) when is_integer(code), do: Tracer.binary_annotation_delta(:i16, "http.status_code", code)

      @doc "Annotation helper: tag with an HTTP request size (`http.request.size` binary annotation)"
      @spec http_request_size(size :: integer()) :: Api.binary_annotation_delta
      def http_request_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.request.size", size)

      @doc "Annotation helper: tag with an HTTP reponse size (`http.response.size` binary annotation)"
      @spec http_response_size(size :: integer()) :: Api.binary_annotation_delta
      def http_response_size(size) when is_integer(size), do: Tracer.binary_annotation_delta(:i64, "http.response.size", size)

      @doc "Annotation helper: tag with a database query (`sql.query` binary annotation)"
      @spec sql_query(query :: String.t) :: Api.binary_annotation_delta
      def sql_query(query) when is_binary(query), do: Tracer.binary_annotation_delta(:string, "sql.query", query)

      @doc "Annotation helper: tag with an error message (`error` binary annotation)"
      @spec error_message(message :: String.t) :: Api.binary_annotation_delta
      def error_message(message) when is_binary(message), do: Tracer.binary_annotation_delta(:string, :error, message)

      @doc "Annotation helper: tag with a general (key,value,host) binary annotation, determining type of annotation automatically"
      @spec tag(key :: Api.binary_annotation_key, value :: Api.binary_annotation_value, endpoint :: Api.maybe_endpoint) :: Api.binary_annotation_delta
      def tag(key, value, endpoint \\ nil)
      def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_binary(value), do: Tracer.binary_annotation_delta(:string, key, value, endpoint)
      def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_boolean(value), do: Tracer.binary_annotation_delta(:bool, key, value, endpoint)
      def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_integer(value), do: Tracer.binary_annotation_delta(:i64, key, value, endpoint)
      def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)) and is_float(value), do: Tracer.binary_annotation_delta(:double, key, value, endpoint)
      def tag(key, value, endpoint) when (is_binary(key) or is_atom(key)), do: Tracer.binary_annotation_delta(:string, key, inspect(value), endpoint)

      @doc "Annotation helper: create an event annotation, general interface."
      @spec annotation(value :: Api.annotation_value, endpoint :: Api.maybe_endpoint) :: Api.annotation_delta
      def annotation(value, endpoint \\ nil) when is_atom(value) or is_binary(value), do: Tracer.annotation_delta(value, endpoint)

      @doc """
      Annotation helper: create a general binary annotation.

      `type` is one of: `:string`, `:bool`, `:i16`, `:i32`, `:i64`, `:double`, `:bytes`

      ## Example
      ```
      binary_annotation(id, :i16, "tab", 4)
      ```
      """
      @spec binary_annotation(type :: Api.binary_annotation_type, key :: Api.binary_annotation_key, value :: Api.binary_annotation_value, endpoint :: Api.maybe_endpoint) :: Api.binary_annotation_delta
      def binary_annotation(type, key, value, endpoint \\ nil) when type in @binary_annotation_types do
        Tracer.binary_annotation_delta(type, key, value, endpoint)
      end

    end
  end
end
