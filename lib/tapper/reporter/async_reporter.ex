defmodule Tapper.Reporter.AsyncReporter do
  @moduledoc """
  Reporter that collects spans and forwards them periodically.

  ## Configuration

  | key | purpose | default/required |
  | `flush_interval` | Milliseconds to wait between reporting a new batch of spans | 10000 |
  | `sender` | Sender to use when reporting a batch. (e.g. Tapper.Reporter.Zipkin) | Required |
  | `max_concurrent_flush_count` | Number of flushes that can work concurrently before we start discarding new spans | 5 |
  | `max_spans_threshold` | Reaching this number of spans will reset the flush_interval timer and will flush the spans | 1000 |

  e.g.
  ```
  config :tapper,
    system_id: "my-application",
    reporter: Tapper.Reporter.AsyncReporter

  config :tapper, Tapper.Reporter.AsyncReporter,
    flush_interval: 10000,
    max_spans_threshold: 1000,
    max_concurrent_flush_count: 5,
    sender: Tapper.Reporter.Zipkin

  config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "https://my-zipkin.domain.com:9411/api/v1/spans",
    client_opts: [timeout: 10000]
  """

  use GenServer

  require Logger

  @behaviour Tapper.Reporter.Api

  # 10 seconds
  @default_flush_interval 10000

  @default_max_concurrent_flush_count 5

  @default_max_spans_threshold 1000

  @default_sender Tapper.Reporter.Console

  # Client

  def start_link(spans \\ [], opts \\ []) do
    Logger.info("Starting Tapper.Reporter.AsyncReporter")

    config = Application.get_env(:tapper, __MODULE__)
    flush_interval = opts[:flush_interval] || config[:flush_interval] || @default_flush_interval
    sender = opts[:sender] || config[:sender] || @default_sender

    max_concurrent_flush_threshold =
      opts[:max_concurrent_flush_threshold] || config[:max_concurrent_flush_threshold] ||
        @default_max_concurrent_flush_count

    max_spans_threshold =
      opts[:max_spans_threshold] || config[:max_spans_threshold] || @default_max_spans_threshold

    GenServer.start_link(
      __MODULE__,
      %{
        flush_interval: flush_interval,
        spans: spans,
        sender: sender,
        max_concurrent_flush_threshold: max_concurrent_flush_threshold,
        max_spans_threshold: max_spans_threshold
      },
      name: __MODULE__
    )
  end

  @impl true
  def ingest(spans) when is_list(spans) do
    GenServer.cast(__MODULE__, {:ingest, spans})
  end

  def flush do
    GenServer.call(__MODULE__, :flush_now)
  end

  # Server

  @impl true
  def init(state) do
    {:ok, flushing_counter} = Agent.start_link(fn -> 0 end, name: :async_reporter_flushing_count)

    {:ok, Map.merge(%{flushing_counter: flushing_counter}, schedule_flush(state))}
  end

  @impl true
  def handle_cast(
        {:ingest, new_spans},
        %{spans: spans, max_spans_threshold: max_spans_threshold} = state
      ) do
    state = %{state | spans: spans ++ new_spans}

    if length(state[:spans]) >= max_spans_threshold do
      {:noreply, flush!(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:flush_now, _from, state) do
    {:reply, :ok, flush!(state)}
  end

  @impl true
  def handle_info(:flush, state) do
    {:noreply, flush!(state)}
  end

  defp flush!(%{spans: spans, sender: sender} = state) when length(spans) > 0 do
    with :ok <- prepare_for_flush(state) do
      Task.start(fn ->
        try do
          sender.ingest(spans)
        after
          finish_flush(state)
        end
      end)
    end

    %{schedule_flush(state) | spans: []}
  end

  defp flush!(state), do: state

  defp schedule_flush(%{flush_interval: flush_interval} = state) do
    if state[:timer] do
      Process.cancel_timer(state[:timer])
    end

    timer = Process.send_after(self(), :flush, flush_interval)
    Map.merge(state, %{timer: timer})
  end

  defp prepare_for_flush(%{
         flushing_counter: flushing_counter,
         max_concurrent_flush_threshold: max_concurrent_flush_threshold
       }) do
    Agent.get_and_update(flushing_counter, fn count ->
      if count < max_concurrent_flush_threshold do
        {:ok, count + 1}
      else
        {:error, count}
      end
    end)
  end

  defp finish_flush(%{flushing_counter: flushing_counter}) do
    Agent.update(flushing_counter, fn count -> count - 1 end)
  end
end
