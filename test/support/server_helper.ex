defmodule Test.Helper.Server do
    def config() do
        %{
            host_info: %{
                ipv4: {2,1,1,2},
                system_id: "default-host"
            }
        }
    end

    def random_endpoint() do
        n = :rand.uniform(254)
        p = :rand.uniform(9999)
        %Tapper.Endpoint{
            ipv4: {n,n,n,n+1},
            port: p,
            service_name: Integer.to_string(n) <> ":" <> Integer.to_string(p)
        }
    end

    def init_with_opts(opts \\ []) do
        config = opts[:config] || config()
        trace_id = Tapper.TraceId.generate()
        span_id = Tapper.SpanId.generate()
        timestamp = System.os_time(:microseconds)

        {:ok, trace, _ttl} = Tapper.Tracer.Server.init([config, {trace_id, span_id, :root, true, false}, self(), timestamp, opts])
        {trace, span_id}
    end

end