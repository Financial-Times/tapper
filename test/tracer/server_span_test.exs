defmodule Tracer.Server.SpanTest do
    use ExUnit.Case

    import Test.Helper.Server

    require Logger

    def new_agent() do
        {:ok, agent} = Agent.start_link(fn -> nil end)
        agent
    end

    def agent_updater(agent) do
        fn(state) -> 
            Agent.update(agent, fn(_) -> state end)
        end
    end

    def agent_get(agent) do
        Agent.get(agent, &(&1))
    end 

    test "finish normally" do

        agent = new_agent()

        {trace, span_id} = init_with_opts(config: put_in(config()[:reporter], agent_updater(agent)))
        timestamp = System.os_time(:microseconds)

        {:stop, :normal, []} =
            Tapper.Tracer.Server.handle_cast({:finish, timestamp, []}, trace)

        spans = agent_get(agent)

        assert is_list(spans)
        assert length(spans) == 1
    end

    test "finish async" do

        agent = new_agent()

        config = put_in(config()[:reporter], agent_updater(agent))
        {trace, span_id} = init_with_opts(config: config)
        timestamp = System.os_time(:microseconds)

        {:noreply, state, _ttl} =
            Tapper.Tracer.Server.handle_cast({:finish, timestamp, [async: true]}, trace)

        spans = agent_get(agent)

        assert spans == nil

        annotations = state.spans[trace.span_id].annotations

        assert is_list(annotations)
        assert length(annotations) == 2

        assert hd(annotations) == %Tapper.Tracer.Trace.Annotation{
            value: :async,
            timestamp: timestamp,
            host: Tapper.Tracer.Server.endpoint_from_config(config)
        }
    end

end