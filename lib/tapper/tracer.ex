defmodule Tapper.Tracer do
  @moduledoc """
  Low-level client API, interfaces between a Tapper client and a `Tapper.Tracer.Server`.

  Most functions in `Tapper` delegate to this module; `Tapper` also provides helper functions
  for creation of common annotations.

  For protection against future API changes, prefer the higher-level interfaces.

  ## See also

  * `Tapper` - high-level client API.
  * `Tapper.Ctx` - high-level contextual client API.

  """

  @behaviour Tapper.Tracer.Api

  use Bitwise

  require Logger

  import Tapper.Tracer.Server, only: [via_tuple: 1]

  alias Tapper.Timestamp
  alias Tapper.Tracer.Trace
  alias Tapper.Tracer.Api

  @doc """
  start a new root trace, e.g. on originating a request, e.g.:

  ```
  id = Tapper.start(name: "request resource", type: :client, remote: remote_endpoint)
  ```

  ### Options

  * `name` - the name of the span.
  * `sample` (boolean) - whether to sample this trace or not.
  * `debug` (boolean) - the debugging flag, if `true` this turns sampling for this trace on, regardless of
    the value of `sample`.
  * `annotations` (list, atom or tuple) - a single annotation or list of annotations, specified by `Tapper.tag/3` etc.
  * `type` (`:client` | `:server`) - the type of the span; defaults to `:client` <sup>1</sup>.
  * `remote` - the remote `Tapper.Endpoint`: creates a "sa" (client) or "ca" (server) binary annotation on this span.
  * `ttl` - how long this span should live before automatically finishing it
    (useful for long-running async operations); milliseconds.
  * `reporter` (module atom or function) - override the configured reporter for this trace; useful for testing.

  <sup>1</sup> determines the type of an automatically created `sr` (type `:server`) or `cs` (type `:client`) annotation, see also `Tapper.client_send/0` and `Tapper.server_receive/0`.

  #### Notes
  * If neither `sample` nor `debug` are set, all operations on this trace become a no-op.

  """
  def start(opts \\ []) when is_list(opts) do
    trace_id = Tapper.TraceId.generate()
    span_id = elem(trace_id, 0) &&& 0xFFFFFFFFFFFFFFFF # lower 64 bits
    timestamp = Timestamp.instant()

    # check and default options
    {opts, sample, debug} = preflight_opts(opts, :client)

    id = Tapper.Id.init(trace_id, span_id, :root, sample, debug)

    # don't even start tracer if sampled is false
    if id.sampled do
      trace_init = {trace_id, span_id, :root, sample, debug, false}

      {:ok, _pid} = Tapper.Tracer.Supervisor.start_tracer(trace_init, timestamp, opts)
    end

    # Logger.metadata(trace_id: %Tapper.TraceId{value: trace_id})
    metadata(trace_id)

    id
  end

  @doc """
  join an existing trace, e.g. server recieving an annotated request, returning a `Tapper.Id` for subsequent operations:
  ```
  id = Tapper.join(trace_id, span_id, parent_id, sample, debug, name: "receive request")
  ```

  NB Probably called by an integration (e.g. [`tapper_plug`](https://github.com/Financial-Times/tapper_plug))
  with name, annotations etc. added in the service code, so the name is optional here, see `Tapper.name/1`.

  ## Arguments

  * `trace_id` - the incoming trace id.
  * `span_id` - the incoming span id.
  * `parent_span_id` - the incoming parent span id, or `:root` if none.
  * `sample` is the incoming sampling status; `true` implies trace has been sampled, and
  down-stream spans should be sampled also, `false` that it will not be sampled,
  and down-stream spans should not be sampled either.
  * `debug` is the debugging flag, if `true` this turns sampling for this trace on, regardless of
  the value of `sampled`.


  ## Options
  * `name` (String) name of span, see also `Tapper.name/1`.
  * `annotations` (list, atom or tuple) - a single annotation or list of annotations, specified by `Tapper.tag/3` etc.
  * `type` - the type of the span, i.e.. `:client`, `:server`; defaults to `:server`; determines which of `sr` (`:server`) or `cs`
    (`:client`) annotations is added. Defaults to `:server`.
  * `endpoint` - sets the endpoint for the initial `cr` or `sr` annotation, defaults to one derived from Tapper configuration (see `Tapper.Application.start/2`).
  * `remote` (`Tapper.Endpoint`) - the remote endpoint: automatically creates a "sa" (`:client`) or "ca" (`:server`) binary annotation on this span, see also `Tapper.server_address/1`.
  * `ttl` - how long this span should live between operations, before automatically finishing it
    (useful for long-running async operations); milliseconds.
  * `reporter` (module atom or function) - override the configured reporter for this trace; useful for testing.

  #### Notes

  * If neither `sample` nor `debug` are set, all operations on this trace become a no-op.
  * `type` determines the type of an automatically created `sr` (`:server`) or `cs` (`:client`) annotation, see also `Tapper.client_send/0` and `Tapper.server_receive/0`.
  """
  def join(trace_id, span_id, parent_id, sample, debug, opts \\ []), do: join({trace_id, span_id, parent_id, sample, debug}, opts)
  def join({trace_id, span_id, parent_id, sample, debug}, opts \\ []) when is_list(opts) do

    timestamp = Timestamp.instant()

    # check and default options
    {opts, _sample, _trace} = preflight_opts(opts, :server)

    id = Tapper.Id.init(trace_id, span_id, parent_id, sample, debug)

    trace_init = {trace_id, span_id, parent_id, sample, debug, true}

    if id.sampled do
      {:ok, _pid} = Tapper.Tracer.Supervisor.start_tracer(trace_init, timestamp, opts)
    end

    # Logger.metadata(trace_id: %Tapper.TraceId{value: trace_id})
    metadata(trace_id)

    id
  end

  # roll our own Logger.metadata since generic fn is too slow; this is 2x
  defp metadata(trace_id) do
    trace_meta = {:trace_id, %Tapper.TraceId{value: trace_id}}
    case :erlang.get(:logger_metadata) do
      :undefined -> :erlang.put(:logger_metadata, {true, [trace_meta]})
      {enabled, metadata} ->
        :erlang.put(:logger_metadata, {
          enabled,
          :lists.keystore(:trace_id, 1, metadata, trace_meta)
        })
    end
  end

  defp remove_metadata do
    case :erlang.get(:logger_metadata) do
      :undefined -> :ok
      {enabled, metadata} ->
        :erlang.put(:logger_metadata, {
          enabled,
          :lists.keydelete(:trace_id, 1, metadata)
        })
        :ok
    end
  end

  @doc false
  # ensure options are correct or default them, and pickup sample and debug flags.
  #
  # NB this was previously performed by two functions and multiple Keyword.get/Access calls;
  # this rolls it all together, so keyword list is only processed once, as an optimisation
  # (but IMHO it actually reads better than the original too).
  # A better optimisation would to not check/default opts at all on the client side,
  # but we still need the sample and debug opts for start/1, unless we change the API
  # to take them as parameters...
  @spec preflight_opts(opts :: Keyword.t, default_type :: Api.span_type) :: {opts :: Keyword.t, sample :: boolean, debug :: boolean}
  def preflight_opts(opts, default_span_type) do
    Enum.reduce(opts, {[{:type, default_span_type}], false, false}, fn

      (elem = {:type, :client}, {new_opts, sample, debug}) ->
        {[elem | new_opts], sample, debug}
      (elem = {:type, :server}, {new_opts, sample, debug}) ->
        {[elem | new_opts], sample, debug}
      ({:type, other}, _) ->
        raise ArgumentError, "type should be :client or :server, got #{inspect other}"

      ({:sample, true}, {new_opts, _sample, debug}) ->
        {new_opts, true, debug}

      ({:debug, true}, {new_opts, sample, _debug}) ->
        {new_opts, sample, true}

      (elem = {:remote, %Tapper.Endpoint{}}, {new_opts, sample, debug}) ->
        {[elem | new_opts], sample, debug}
      (elem = {:remote, nil}, {new_opts, sample, debug}) ->
        {[elem | new_opts], sample, debug}
      ({:remote, other}, _) ->
        raise ArgumentError, "endpoint if specified should be %Tapper.Endpoint{} or nil, got #{inspect other}"

      (elem, {new_opts, sample, debug}) ->
        {[elem | new_opts], sample, debug}
    end)
  end

  @doc """
  Finishes the trace, returns `:ok`.

  For `async` processes (where spans persist in another process), just call
  `finish/2` when done with the main span, passing the `async` option, and finish
  child spans as normal using `finish_span/2`. When the trace times out, spans will
  be sent to the server, marking any unfinished spans with a `timeout` annotation.

  ```
  id = Tapper.finish(id, async: true, annotations: [Tapper.http_status_code(401)])
  ```

  ## Options
  * `async` (boolean) - mark the trace as asynchronous, allowing child spans to finish within the TTL.
  * `annotations` (list) - list of annotations to attach to main span.

  ## See also
  * `Tapper.Tracer.Timeout` - timeout behaviour.
  * `Tapper.async/0` annotation.
  """
  def finish(id, opts \\ [])
  def finish(%Tapper.Id{sampled: false}, _opts), do: :ok
  def finish(id = %Tapper.Id{}, opts) when is_list(opts) do
    end_timestamp = Timestamp.instant()

    remove_metadata()
    GenServer.cast(via_tuple(id), {:finish, end_timestamp, opts})
  end


  @doc """
  Starts a child span, returning an updated `Tapper.Id`.

  ## Arguments
  * `id` - Tapper id.
  * `options` - see below.

  ## Options
  * `name` (string) - name of span.
  * `local` (string) - provide a local span context name (via a `lc` binary annotation).
  * `annotations` (list, atom or tuple) - a list of annotations to attach to the span.

  ```
  id = Tapper.start_span(id, name: "foo", local: "do foo", annotations: [Tapper.sql_query("select * from foo")])
  ```
  """
  def start_span(id, opts \\ [])

  def start_span(:ignore, _opts), do: :ignore

  def start_span(id = %Tapper.Id{sampled: false}, _opts), do: id

  def start_span(id = %Tapper.Id{span_id: span_id}, opts) when is_list(opts) do
    timestamp = Timestamp.instant()

    child_span_id = Tapper.SpanId.generate()

    updated_id = Tapper.Id.push(id, child_span_id)

    span = %Trace.SpanInfo {
      id: child_span_id,
      start_timestamp: timestamp,
      parent_id: span_id,
      annotations: [],
      binary_annotations: []
    }

    GenServer.cast(via_tuple(id), {:start_span, span, opts})

    updated_id
  end

  @doc """
  Finish a nested span, returning an updated `Tapper.Id`.

  ## Arguments
  * `id` - Tapper id.

  ## Options
  * `annotations` (list, atom, typle) - a list of annotations to attach the the span.

  ```
  id = finish_span(id, annotations: Tapper.http_status_code(202))
  ```
  """
  def finish_span(id, opts \\ [])

  def finish_span(:ignore, _), do: :ignore

  def finish_span(id = %Tapper.Id{sampled: false}, _), do: id

  def finish_span(id = %Tapper.Id{}, opts) do

    timestamp = Timestamp.instant()

    GenServer.cast(via_tuple(id), {:finish_span, id.span_id, timestamp, opts})

    Tapper.Id.pop(id)
  end

  @doc "build an name-span action, suitable for passing to `annotations` option or `update_span/3`; see also `Tapper.name/1`."
  @spec name_delta(name :: String.t | atom) :: Api.name_delta
  def name_delta(name) when is_binary(name) or is_atom(name) do
    {:name, name}
  end

  @doc "build an async action, suitable for passing to `annotations` option or `update_span/3`; see also `Tapper.async/0`."
  @spec async_delta() :: Api.async_delta
  def async_delta do
    {:async, true}
  end

  @doc "build a span annotation, suitable for passing to `annotations` option or `update_span/3`; see also convenience functions in `Tapper`."
  @spec annotation_delta(value :: Api.annotation_value(), endpoint :: Api.maybe_endpoint) :: Api.annotation_delta
  def annotation_delta(value, endpoint \\ nil) when is_atom(value) or is_binary(value) do
    value = map_annotation_type(value)
    endpoint = check_endpoint(endpoint)
    {:annotate, {value, endpoint}}
  end

  @binary_annotation_types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

  @doc "build a span binary annotation, suitable for passing to `annotations` option or `update_span/3`; see also convenience functions in `Tapper`."
  @spec binary_annotation_delta(type :: Api.binary_annotation_type, key :: Api.binary_annotation_key, value :: Api.binary_annotation_value, endpoint :: Api.maybe_endpoint) :: Api.binary_annotation_delta
  def binary_annotation_delta(type, key, value, endpoint \\ nil) when type in @binary_annotation_types and (is_atom(key) or is_binary(key)) do
    endpoint = check_endpoint(endpoint)
    {:binary_annotate, {type, key, value, endpoint}}
  end

  @doc """
  Add annotations to the current span; returns the same `Tapper.Id`.

  ## Arguments
  * `id` - Tapper id.
  * `deltas` - list, or single annotation tuple/atom. See helper functions.
  * `opts` - keyword list of options.

  ## Options
  * `timestamp` - an alternative timestamp for these annotations, e.g. from `Tapper.Timestamp.instant/0`.

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
  @spec update_span(id :: Tapper.Id.t, deltas :: Api.delta() | [Api.delta()], opts :: Keyword.t) :: Tapper.Id.t
  def update_span(id, deltas, opts \\ [])

  def update_span(:ignore, _deltas, _opts), do: :ignore

  def update_span(id = %Tapper.Id{sampled: false}, _, _), do: id

  def update_span(id = %Tapper.Id{}, [], _opts), do: id

  def update_span(id = %Tapper.Id{}, nil, _opts), do: id

  def update_span(id = %Tapper.Id{span_id: span_id}, deltas, opts) do
    timestamp = opts[:timestamp] || Timestamp.instant()

    GenServer.cast(via_tuple(id), {:update, span_id, timestamp, deltas})

    id
  end

  @doc false
  def whereis(:ignore), do: []
  def whereis(%Tapper.Id{trace_id: trace_id}), do: whereis(trace_id)
  def whereis(trace_id) do
    Registry.lookup(Tapper.Tracers, trace_id)
  end

  @doc false
  def check_endpoint(nil), do: nil
  def check_endpoint(endpoint = %Tapper.Endpoint{}), do: endpoint

  @doc """
  Provides some aliases for event annotation types:

  | alias | annotation value |
  | -- | -- |
  | :client_send | `cs` |
  | :client_recv | `cr` |
  | :server_send | `ss` |
  | :server_recv | `sr` |
  | :wire_send | `ws` |
  | :wire_recv | `wr` |
  """
  def map_annotation_type(type) when is_atom(type) do
    case type do
      :client_send -> :cs
      :client_recv -> :cr
      :server_send -> :ss
      :server_recv -> :sr
      :wire_send -> :ws
      :wire_recv -> :wr
      _ -> type
    end
  end

end
