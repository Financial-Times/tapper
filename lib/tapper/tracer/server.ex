defmodule Tapper.Tracer.Server do
  @moduledoc """
  The Trace server.

  There is one server per trace, which persists until the trace is finished, at which point it sends its spans to a reporter.
  """

  use GenServer

  require Logger

  alias Tapper.Tracer.Trace
  alias Tapper.Tracer.Annotations
  alias Tapper.Timestamp

  @doc """
  Starts a Tracer, registering a name derived from the `Tapper.Id`.

  ## Arguments
  * `config` - worker config from `Tapper.Tracer.Supervisor` worker spec.
  * `trace_init` - trace parameters (trace_id, span_id, etc.)
  * `pid` - pid of process that called `Tapper.start/1` or `Tapper.join/6`.
  * `timestamp` (`Tapper.Timestamp.t`) - timestamp of trace receive/start event.
  * `opts` - options which were passed to start or join, see `Tapper.Tracer.Server.init/1`.

  NB called by `Tapper.Tracer.Supervisor` when starting a trace with `start_tracer/2`.

  ## See also
  * `init/1`.
  """
  def start_link(config, trace_init = {trace_id, _, _, _, _}, pid, timestamp, opts) do
    Logger.debug(fn -> inspect {"Tracer: start_link", trace_init} end)

    GenServer.start_link(Tapper.Tracer.Server, [config, trace_init, pid, timestamp, opts], name: via_tuple(trace_id)) # calls Tapper.Tracer.Server.init/1
  end

  @doc "locate the server via the `Tapper.Id`."
  def via_tuple(%Tapper.Id{trace_id: trace_id}), do: via_tuple(trace_id)
  def via_tuple(trace_id) do
    {:via, Registry, {Tapper.Tracers, trace_id}}
  end

  @doc """
  Initializes the Tracer's state.

  ## Arguments (as list)
  * `config` - worker config from Tapper.Tracer.Supervisor's worker spec.
  * `trace_init` - trace parameters i.e. `{trace_id, span_id, parent_span_id, sample, debug}`
  * `pid` - pid of process that called `Tapper.start/1` or `Tapper.join/6`.
  * `timestamp` (`Tapper.Timestamp.t`) - timestamp of trace receive/start event.
  * `opts` - options passed to start or join, see below.

  ## Options
  * `name` (`String`) - name of the span.
  * `annotations` - a list of annotations, specified by `Tapper.Tracer.annotation_delta/2` etc.
  * `type` (`:client` or `:server`) - determines whether the first annotation should be `cs` (`:client`) or `sr` (`:server`).
  * `endpoint` (`Tapper.Endpoint`) - sets the endpoint for the initial `cr` or `sr` annotation, defaults to one derived from Tapper configuration (see `Tapper.Application`).
  * `remote` (`Tapper.Endpoint`) - an endpoint to set as the `sa` (:client) or `ca` (:server) binary annotation.
  * `ttl` (integer, ms) - set the no-activity time-out for this trace in milliseconds; defaults to 30,000 ms.
  * `reporter` (module atom or function) - override the configured reporter for this trace; useful for testing.

  NB passed the list of arguments supplied by `Tapper.Tracer.Server.start_link/5` via `Tapper.Tracer.Supervisor.start_tracer/3`.
  """
  def init([config, trace_init = {trace_id, span_id, parent_id, sample, debug}, _pid, timestamp, opts]) do
    Logger.debug(fn -> inspect {"Tracer: started tracer", trace_init} end)

    Logger.info(fn -> "Start Trace #{Tapper.TraceId.format(trace_id)}" end)

    # override the reporter config, if specified
    config = if(opts[:reporter], do: %{config | reporter: opts[:reporter]}, else: config)

    # this is the local host for `cs` or `sr`: can be overridden by an API client, e.g. if needs to be dynamically generated.
    endpoint = %Tapper.Endpoint{} = (opts[:endpoint] || Trace.endpoint_from_config(config))

    # we shouldn't be stopped by the exit of the process that started the trace because async
    # processes may still be processing; we use either an explicit `finish/2` or
    # the `ttl` option to terminate hanging traces.
    ttl = case Keyword.get(opts, :ttl) do
        ms when is_integer(ms) -> ms
        _ -> 30_000
    end

    span_info = initial_span_info(span_id, parent_id, timestamp, endpoint, opts)

    trace = %Trace{
        config: config,
        trace_id: trace_id,
        span_id: span_id,
        parent_id: parent_id,
        spans: %{
            span_id => span_info # put initial span in span-map
        },
        sample: sample,
        debug: debug,
        timestamp: timestamp,
        last_activity: timestamp,
        ttl: ttl
    }

    # apply any specified annotations
    trace = apply_updates(trace, opts[:annotations], span_id, timestamp, endpoint)

    {:ok, trace, ttl}
  end

  @doc """
  Handles time-out.

  Invoked if ttl expires between messages: automatically ends trace, annotating any un-finished spans.

  ## See also
  * `Tapper.start/1` and `Tapper.join/6` - setting the TTL for a trace using the `ttl` option.
  * `Tapper.finish/2` and `Tapper.async/1` - declaring a trace or span asynchronous.
  * `Tapper.Tracer.Timeout` - timeout behaviour.
  """
  def handle_info(:timeout, trace = %Trace{}) do
    Logger.debug(fn -> inspect({trace.trace_id, :timeout}) end)
    timestamp = Timestamp.instant()

    trace = Tapper.Tracer.Timeout.timeout_trace(trace, timestamp)

    :ok = report_trace(trace)

    Logger.info(fn -> "End Trace #{Tapper.TraceId.format(trace.trace_id)} (timeout)" end)
    {:stop, :normal, []}
  end

  @doc "via Tapper.Tracer.finish/2"
  def handle_cast(msg = {:finish, timestamp, opts}, trace) do
    Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

    trace = apply_updates(trace, opts[:annotations], trace.span_id, timestamp, Trace.endpoint_from_config(trace.config))

    case trace.async || opts[:async] do
      true ->
        Logger.info(fn -> "Finish Trace #{Tapper.TraceId.format(trace.trace_id)} ASYNC" end)
        trace = case Trace.has_annotation?(trace, trace.span_id, :async) do
          false ->
            async_annotation = Annotations.annotation(:async, timestamp, Trace.endpoint_from_config(trace.config))
            update_span(trace, trace.span_id, fn(span) -> %{span | annotations: [async_annotation | span.annotations]} end)
          true -> trace
        end
        trace = %Trace{trace | last_activity: timestamp, async: true}

        {:noreply, trace, trace.ttl}
      _ ->
        trace = %Trace{trace | end_timestamp: timestamp}

        :ok = report_trace(trace)

        Logger.info(fn -> "Finish Trace #{Tapper.TraceId.format(trace.trace_id)}" end)
        {:stop, :normal, []}
    end
  end

  @doc "via start_span/1"
  def handle_cast(msg = {:start_span, span_info, opts}, trace) do
    Logger.debug(fn -> inspect({Tapper.TraceId.format(trace.trace_id), msg}) end)

    config_endpoint = Trace.endpoint_from_config(trace.config)

    span_info = case opts[:local] do
      val when not is_nil(val) ->
          annotation = Trace.BinaryAnnotation.new(:lc, val, :string, config_endpoint)
          update_in(span_info.binary_annotations, &([annotation | &1]))
      _ -> span_info
    end

    trace = put_in(trace.spans[span_info.id], span_info)
    trace = put_in(trace.last_activity, span_info.start_timestamp)
    trace = apply_updates(trace, opts[:annotations], span_info.id, span_info.start_timestamp, config_endpoint)

    {:noreply, trace, trace.ttl}
  end

  @doc "via Tapper.Tracer.finish_span/2"
  def handle_cast(msg = {:finish_span, span_id, timestamp, opts}, trace) do
    Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

    trace = update_span(trace, span_id, fn(span) -> put_in(span.end_timestamp, timestamp) end)

    trace = put_in(trace.last_activity, timestamp)
    trace = apply_updates(trace, opts[:annotations], span_id, timestamp, opts[:endpoint] || Trace.endpoint_from_config(trace.config))

    {:noreply, trace, trace.ttl}
  end

  @doc "via Tapper.Tracer.update/3"
  def handle_cast(msg = {:update, span_id, timestamp, deltas}, trace) do
    Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

    endpoint = Trace.endpoint_from_config(trace.config)

    trace = apply_updates(trace, deltas, span_id, timestamp, endpoint)
    trace = %Trace{trace | last_activity: timestamp}

    {:noreply, trace, trace.ttl}
  end

  def apply_updates(trace, nil, _span_id, _timestamp, _endpoint), do: trace
  def apply_updates(trace, deltas, span_id, timestamp, endpoint) when is_list(deltas) do
    Enum.reduce(deltas, trace, &(apply_update(&1, &2, span_id, timestamp, endpoint)))
  end
  def apply_updates(trace, delta, span_id, timestamp, endpoint) when not is_list(delta) do
    apply_update(delta, trace, span_id, timestamp, endpoint)
  end

  def apply_update({:annotate, {value, endpoint}}, trace = %Trace{}, span_id, timestamp, default_endpoint) do
    annotation = Annotations.annotation(value, timestamp, endpoint || default_endpoint)
    update_span(trace, span_id, fn(span) -> %{span | annotations: [annotation | span.annotations]} end)
  end

  def apply_update({:binary_annotate, {type, key, value, endpoint}}, trace = %Trace{}, span_id, _timestamp, default_endpoint) do
    case Annotations.binary_annotation(type, key, value, endpoint || default_endpoint) do
      nil -> trace
      annotation -> update_span(trace, span_id, fn(span) -> %{span | binary_annotations: [annotation | span.binary_annotations]} end)
    end
  end

  def apply_update({:name, name}, trace = %Trace{}, span_id, _timestamp, _default_endpoint) do
    update_span(trace, span_id, fn(span) -> %{span | name: name} end)
  end

  def apply_update({:async, _}, trace = %Trace{}, span_id, timestamp, default_endpoint) do
    annotation = Annotations.annotation(:async, timestamp, default_endpoint)
    trace = update_span(trace, span_id, fn(span) -> %{span | annotations: [annotation | span.annotations]} end)
    %{trace | async: true}
  end

  def apply_update(value, trace = %Trace{}, span_id, timestamp, default_endpoint) when is_atom(value) do
    annotation = Annotations.annotation(value, timestamp, default_endpoint)
    update_span(trace, span_id, fn(span) -> %{span | annotations: [annotation | span.annotations]} end)
  end

  @doc "update a span (identified by span id) in a trace with an updater function, taking care of case where span does not exist."
  @spec update_span(Trace.t, Tapper.SpanId.t, (Trace.SpanInfo.t -> Trace.SpanInfo.t)) :: Trace.t
  def update_span(trace = %Trace{}, span_id, span_updater) when is_integer(span_id) and is_function(span_updater, 1) do
    case trace.spans[span_id] do
      nil ->
        # if we've been restarted by our supervisor, we may have no record of the span...
        trace
      _span ->
        update_in(trace.spans[span_id], span_updater)
    end
  end

  @doc "prepare the SpanInfo of the initial span in this Tracer"
  def initial_span_info(span_id, parent_id, timestamp, endpoint, opts) do

    type = Keyword.get(opts, :type, :client)

    # a 'shared' root span was not started locally, i.e. we joined it, so we won't set the end_timestamp
    # see http://zipkin.io/pages/instrumenting.html#timestamps-and-duration
    shared = (type == :server)

    annotation_type = case type do
      :server -> :sr
      :client -> :cs
    end

    name = Keyword.get(opts, :name, "unknown")

    binary_annotations = add_remote_address_annotation([], annotation_type, opts)

    %Trace.SpanInfo {
      name: name,
      id: span_id,
      parent_id: parent_id,
      shared: shared,
      start_timestamp: timestamp,
      annotations: [%Trace.Annotation{
        timestamp: timestamp,
        value: annotation_type,
        host: endpoint
      }],
      binary_annotations: binary_annotations
    }
  end

  @doc false
  def add_remote_address_annotation(annotations, span_type, opts) do
    case {span_type, opts[:remote]} do
      {:sr, client_endpoint = %Tapper.Endpoint{}} ->
        [Annotations.binary_annotation(:ca, client_endpoint) | annotations]

      {:cs, server_endpoint = %Tapper.Endpoint{}} ->
        [Annotations.binary_annotation(:sa, server_endpoint) | annotations]

      _else -> annotations
    end
  end

  @doc "convert trace to protocol spans, and invoke reporter module or function."
  def report_trace(trace = %Trace{}) do
    Logger.debug(fn -> "Sending trace #{inspect trace}" end)

    spans = Trace.Convert.to_protocol_spans(trace)

    case trace.config.reporter do
      fun when is_function(fun, 1) -> fun.(spans)
      mod when is_atom(mod) -> apply(mod, :ingest, [spans])
    end

    :ok
  end

end
