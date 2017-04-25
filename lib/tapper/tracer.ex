defmodule Tapper.Tracer do

    @behaviour Tapper.Tracer.Api

    use Bitwise

    require Logger

    import Tapper.Tracer.Server, only: [via_tuple: 1]
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

    def whereis(%Tapper.Id{trace_id: trace_id}), do: whereis(trace_id)
    def whereis(trace_id) do
        Registry.lookup(Tapper.Tracers, trace_id)
    end

end