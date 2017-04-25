defmodule Tapper.Tracer.Server do
    use GenServer

    require Logger

    alias Tapper.Tracer.Trace

    @doc """
    Starts a Tracer, registering a name derived from the Tapper trace_id.

    NB called by Tapper.TracerSupervisor when starting a trace with `start_tracer/2`.
    """
    def start_link(config, trace_init = {trace_id, _, _, _, _}, pid, timestamp, opts) do
        Logger.debug(fn -> inspect {"Tracer: start_link", trace_init} end)
        GenServer.start_link(Tapper.Tracer.Server, [config, trace_init, pid, timestamp, opts], name: via_tuple(trace_id)) # calls Tapper.Tracer.Server.init/1
    end

    @doc """
    Initializes the Tracer's state.

    NB passed the arguments supplied by `Tapper.Tracer.Server.start_link/4` via `Tapper.TracerSupervisor.start_tracer/3`.
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

    def report_trace(trace = %Trace{}) do
        Logger.debug(fn -> "Sending trace #{inspect trace}" end)

        spans = Trace.to_protocol_spans(trace)

        apply(trace.config.reporter, :ingest, [spans])
    end

    def via_tuple(%Tapper.Id{trace_id: trace_id}), do: via_tuple(trace_id)
    def via_tuple(trace_id) do
        {:via, Registry, {Tapper.Tracers, trace_id}}
    end

end
