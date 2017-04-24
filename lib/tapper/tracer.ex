defmodule Tapper.Tracer do
    use GenServer
    use Bitwise
    require Logger

    @behaviour Tapper.Tracer.Api

    alias Tapper.Tracer.Trace

    @doc """
        start a new root trace, e.g. on originating a request, e.g.:

        ```
        id = Tapper.Tracer.start(name: "request resource", type: :client)
        ```

        Options:

           * `name` - the name of the span.
           * `sample` - boolean, whether to sample this trace or not.
           * `debug` - boolean, enabled debug.
           * `type` - the type of the span, i.e.. `:client`, `:server`; defaults to `:client`.
           * `endpoint` - the remote Endpoint (when `:client`).
           * `ttl` - how long this span should live before automatically finishing it 
             (useful for long-running async operations); milliseconds.

        NB if neither `sample` nor `debug` are set, all operations on this trace become a no-op.
    """
    def start(opts \\ []) when is_list(opts) do
        trace_id = Tapper.TraceId.generate()
        span_id = elem(trace_id,0) &&& 0xFFFFFFFFFFFFFFFF # lower 64 bits
        timestamp = System.os_time(:microseconds)

        # check and default type to :client
        opts = default_type_opts(opts, :client) # if we're starting a trace, we're a client
        :ok = check_endpoint_opt(opts) # if we're sending an endpoint, check it's an %Endpoint{}

        sample = Keyword.get(opts, :sample, false) === true
        debug = Keyword.get(opts, :debug, false) === true

        sampled = sample || debug

        # don't even start tracer if sampled is false
        if sampled do
            trace_init = {trace_id, span_id, :root, sample, debug}

            Tapper.TracerSupervisor.start_tracer(trace_init, timestamp, opts)
        end

        id = %Tapper.Id{
            trace_id: trace_id,
            span_id: span_id,
            parent_ids: [],
            sampled: sampled
        }

        Logger.metadata(tapper_id: id)

        id
    end

    defp default_type_opts(opts, default) when default in [:client,:server] do
        {_, opts} = Keyword.get_and_update(opts, :type, fn(value) -> 
            case value do
                nil -> {value, default}
                :client -> {value, :client}
                :server -> {value, :server}
            end
        end)
        opts
    end

    defp check_endpoint_opt(opts) do
        case opts[:endpoint] do
            nil -> :ok
            _endpoint = %Trace.Endpoint{} -> :ok
            _ -> {:error, "invalid endpoint: expected struct %Tapper.Tracer.Trace.Endpoint{}"}
        end
    end

    @doc """
        join an existing trace, e.g. server recieving an annotated request.
        ```
        id = Tapper.Tracer.join(trace_id, span_id, parent_id, sampled, debug, name: "receive request")
        ```
        NB The id could be generated at the top level, and annotations, name etc. set
        deeper in the service code, so the name is optional here.

        ### Arguments

           * `sampled` is the incoming sampling status; `true` implies trace has been sampled, and
            down-stream spans should be sampled also, `false` that it will not be sampled,
            and down-stream  spans should not be sampled either.
           * `debug` is the debugging flag, if `true` this turns sampling for this trace on, regardless of 
           the value of `sampled`.

        ### Options
           * `name` name of span
           * `type` - the type of the span, i.e.. :client, :server; defaults to `:server`.
           * `endpoint` - the remote Endpoint (`:client`).
           * `ttl` - how long this span should live before automatically finishing it 
             (useful for long-running async operations); milliseconds.

        NB if neither `sample` nor `debug` are set, all operations on this trace become a no-op.
    """
    def join(trace_id, span_id, parent_id, sample, debug, opts \\ []), do: join({trace_id, span_id, parent_id, sample, debug}, opts)
    def join(trace_init = {trace_id, span_id, _parent_id, sample, debug}, opts \\ []) when is_list(opts) do

        timestamp = System.os_time(:microseconds)

        # check and default type to :server
        default_type_opts(opts, :server)
        sampled = sample || debug

        if sampled do
            Tapper.TracerSupervisor.start_tracer(trace_init, timestamp, opts)
        end

        id = %Tapper.Id{
            trace_id: trace_id,
            span_id: span_id,
            parent_ids: [],
            sampled: sampled
        }

        Logger.metadata(tapper_id: id)

        id
    end


    @doc """
        Finishes the trace.

        NB there is no flush(), because we'll always send any spans we have started,
        even if the process that spawned them dies. For async processes, just call 
        finish() when done, possibly setting a more generous TTL.
    """
    def finish(id, opts \\ [])
    def finish(%Tapper.Id{sampled: false}, _opts), do: :ok
    def finish(id = %Tapper.Id{}, opts) when is_list(opts) do
        end_timestamp = System.os_time(:microseconds)

        GenServer.cast(via_tuple(id), {:finish, end_timestamp, opts})
    end


    @doc """
        Starts a child span.

        Options:
           * `name` - name of span
    """
    def start_span(id, opts \\ [])

    def start_span(id = %Tapper.Id{sampled: false}, _opts), do: id

    def start_span(id = %Tapper.Id{span_id: span_id}, opts) when is_list(opts) do
        timestamp = System.os_time(:microseconds)

        child_span_id = Tapper.SpanId.generate()

        updated_id = Tapper.Id.push(id, child_span_id)

        name = Keyword.get(opts, :name, "unknown")

        span = %Trace.SpanInfo {
            name: name,
            id: child_span_id,
            start_timestamp: timestamp,
            parent_id: span_id
        }

        GenServer.cast(via_tuple(id), {:start_span, span, opts})

        updated_id
    end

    def finish_span(id, opts \\ [])

    def finish_span(id = %Tapper.Id{sampled: false}, _opts), do: id

    def finish_span(id = %Tapper.Id{}, opts) do
        
        timestamp = System.os_time(:microseconds)
        
        updated_id = Tapper.Id.pop(id)

        span = %Trace.SpanInfo {
            id: id.span_id,
            parent_id: updated_id.span_id,
            end_timestamp: timestamp
        }

        GenServer.cast(via_tuple(id), {:finish_span, span, opts})

        updated_id
    end

    @doc """
    Starts a Tracer, registering a name derived from the Tapper trace_id.

    NB called by Tapper.TracerSupervisor when starting a trace with `start_tracer/2`.
    """
    def start_link(config, trace_init = {trace_id, _, _, _, _}, pid, timestamp, opts) do
        Logger.debug(fn -> inspect {"Tracer: start_link", trace_init} end)
        GenServer.start_link(Tapper.Tracer, [config, trace_init, pid, timestamp, opts], name: via_tuple(trace_id)) # calls Tapper.Tracer.init/1
    end

    @doc """
    Initializes the Tracer's state.

    NB passed the arguments supplied by `Tapper.Tracer.start_link/4` via `Tapper.TracerSupervisor.start_tracer/3`.
    """
    def init([config, trace_init = {trace_id, span_id, parent_id, sample, debug}, pid, timestamp, opts]) do
        Logger.debug(fn -> inspect {"Tracer: started tracer", trace_init} end)

        Logger.info("Start Trace #{Tapper.TraceId.format(trace_id)}")

        endpoint = case opts[:type] do
            :client -> self_as_endpoint(config)
            :server -> opts[:endpoint]
        end

        # we shouldn't be stopped by our parent's exit, and nor should we finish 
        # the trace on our parent's exit, because async processes may still be processing; 
        # we use either an explicit `finish\1` or the `ttl` option to terminate hanging traces.
        # TODO support `ttl` option
        # Process.unlink(pid)

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
            debug: debug
        }

        {:ok, trace}
    end

    @doc "via finish()"
    # TODO support flush?
    def handle_cast(msg = {:finish, timestamp, _opts}, trace) do
        Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

        trace = %Trace{trace | end_timestamp: timestamp}

        report_trace(trace)

        Logger.info("End Trace #{Tapper.TraceId.format(trace.trace_id)}")
        {:stop, :normal, []}
    end

    @doc "via start_span()"
    def handle_cast(msg = {:start_span, span_info, _opts}, trace) do
        Logger.debug(fn -> inspect({Tapper.TraceId.format(trace.trace_id), msg}) end)

        trace = put_in(trace.spans[span_info.id], span_info)
        trace = put_in(trace.last_activity, span_info.start_timestamp)

        {:noreply, trace}
    end

    @doc "via finish_span()"
    def handle_cast(msg = {:finish_span, span_info, _opts}, trace) do
        Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

        trace = put_in(trace.spans[span_info.id].end_timestamp, span_info.end_timestamp) 
        trace = put_in(trace.last_activity, span_info.end_timestamp)

        {:noreply, trace}
    end

    def handle_cast(msg = {:annotation, span_id, value, timestamp}, trace) do
        Logger.debug(fn -> inspect({trace.trace_id, msg}) end)

        annotation = create_annotation(value, timestamp, trace.config.host_info)
        
        trace = case annotation do
            nil -> trace
            _ -> 
                trace 
                |> update_in([:spans, span_id, :annotations], &([annotation | &1]))
                |> put_in([:last_activity], timestamp)
        end
        {:noreply, trace}
    end

    # TODO merge this and create_endpoint
    def self_as_endpoint(config) do
        %Trace.Endpoint{
            ipv4: config.host_info.ipv4,
            service_name: config.host_info.system_id
        }
    end
    def create_endpoint(%{ipv4: ipv4, system_id: system_id}) do
        %Trace.Endpoint{
            ipv4: ipv4,
            service_name: system_id
        }
    end

    def create_annotation(value, timestamp, host_info) do
        cond do
            value in [:cs,:cr,:ss,:sr,:ws,:wr,:csf,:crf,:ssf,:srf,:error] ->
                Trace.Annotation.new(value, timestamp, create_endpoint(host_info))
            false -> nil
        end
    end

    @doc "prepare the SpanInfo of the initial span in this Tracer"
    def initial_span_info(span_id, parent_id, timestamp, endpoint, opts) do
        
        annotation_type = case Keyword.get(opts, :type, nil) do
            :server -> "sr"
            :client -> "cs"
        end

        name = Keyword.get(opts, :name, "unknown")

        %Trace.SpanInfo {
            name: name,
            id: span_id,
            parent_id: parent_id,
            start_timestamp: timestamp,
            annotations: [%Trace.Annotation{
                timestamp: timestamp,
                value: annotation_type,
                host: endpoint
            }],
            binary_annotations: []
        }
    end

    def via_tuple(%Tapper.Id{trace_id: trace_id}), do: via_tuple(trace_id)
    def via_tuple(trace_id) do
        {:via, Registry, {Tapper.Tracers, trace_id}}
    end

    def whereis(%Tapper.Id{trace_id: trace_id}), do: whereis(trace_id)
    def whereis(trace_id) do
        Registry.lookup(Tapper.Tracers, trace_id)
    end

    def report_trace(trace = %Trace{}) do
        Logger.debug(fn -> "Sending trace #{inspect trace}" end)

        spans = Trace.to_protocol_spans(trace)

        apply(trace.config.reporter, :ingest, [spans])
    end

end
