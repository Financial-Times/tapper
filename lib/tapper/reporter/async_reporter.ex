defmodule Tapper.Reporter.AsyncReporter do
  @moduledoc """
  Reporter that collects spans and forwards them periodically to another reporter.

  ## Configuration

  | key | purpose | default/required |
  | - | - | - |
  | `flush_interval` | Milliseconds to wait between reporting a new batch of spans | 10000 |
  | `sender` | Reporter to use when reporting a batch; see `Tapper.Application` for possible `reporter` forms | Required |
  | `max_concurrent_flush_count` | Number of flushes that can work concurrently before we start discarding new spans | 5 |
  | `max_spans_threshold` | Reaching this number of spans will reset the flush_interval timer and will flush the spans | 1000 |

  e.g.
  ```
  config :tapper,
    system_id: "my-application",
    reporter: {Tapper.Reporter.AsyncReporter, []} # NB started under Tapper supervisor

  config :tapper, Tapper.Reporter.AsyncReporter,
    flush_interval: 10000,
    max_spans_threshold: 1000,
    max_concurrent_flush_count: 5,
    sender: Tapper.Reporter.Zipkin

  # configuration for sender module
  config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "https://my-zipkin.domain.com:9411/api/v1/spans",
    client_opts: [timeout: 10000]
  ```

  """

  require Logger

  use Supervisor

  # Client API

  @behaviour Tapper.Reporter.Api

  @impl true
  def ingest(spans) when is_list(spans) do
    GenServer.cast(__MODULE__.Server, {:ingest, spans})
  end

  def flush do
    GenServer.call(__MODULE__.Server, :flush_now)
  end

  @default_flush_interval 10000

  @default_max_concurrent_flush_count 5

  @default_max_spans_threshold 1000

  @default_sender Tapper.Reporter.Console

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:tapper, __MODULE__)
    flush_interval = opts[:flush_interval] || config[:flush_interval] || @default_flush_interval
    sender = opts[:sender] || config[:sender] || @default_sender

    max_concurrent_flush_threshold =
      opts[:max_concurrent_flush_threshold] || config[:max_concurrent_flush_threshold] ||
        @default_max_concurrent_flush_count

    max_spans_threshold =
      opts[:max_spans_threshold] || config[:max_spans_threshold] || @default_max_spans_threshold

    {sender, sender_spec} =
      case sender do
        {module, _args} = spec -> {module, spec}
        module -> {module, nil}
      end

    Tapper.Reporter.ensure_reporter!(sender)

    config = %{
      flush_interval: flush_interval,
      spans: [],
      sender: sender,
      max_concurrent_flush_threshold: max_concurrent_flush_threshold,
      max_spans_threshold: max_spans_threshold
    }

    children = [
      {__MODULE__.Server, config},
      {DynamicSupervisor,
       name: __MODULE__.WorkerSuper,
       max_children: max_concurrent_flush_threshold,
       strategy: :one_for_one}
    ]

    children =
      if sender_spec do
        Logger.info(fn -> "Supervising reporter module #{Macro.to_string(sender)}" end)
        [sender_spec | children]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Server
  defmodule Server do
    use GenServer

    def start_link(config) do
      Logger.info(fn ->
        "Starting Tapper.Reporter.AsyncReporter with reporter #{Macro.to_string(config.sender)}"
      end)

      GenServer.start_link(__MODULE__, config, name: __MODULE__)
    end

    @impl true
    def init(state) do
      {:ok, schedule_flush(state)}
    end

    @impl true
    def handle_cast(
          {:ingest, new_spans},
          %{spans: spans, max_spans_threshold: max_spans_threshold} = state
        ) do
      state = %{state | spans: spans ++ new_spans}

      if length(state[:spans]) >= max_spans_threshold do
        {:noreply, flush(state)}
      else
        {:noreply, state}
      end
    end

    @impl true
    def handle_call(:flush_now, _from, state) do
      {:reply, :ok, flush(state)}
    end

    @impl true
    def handle_info(:flush, state) do
      {:noreply, flush(state)}
    end

    defp flush(%{spans: []} = state), do: schedule_flush(state)

    defp flush(%{spans: spans, sender: sender} = state) do
      case maybe_send_spans(sender, spans) do
        {:ok, _task} ->
          %{schedule_flush(state) | spans: []}

        {:error, :max_children} ->
          Logger.warn(fn -> "Maximum sender concurrency reached: spans may be dropped." end)
          %{schedule_flush(state) | spans: Enum.take(spans, state.max_spans_threshold)}
      end
    end

    defp schedule_flush(%{flush_interval: flush_interval} = state) do
      if state[:timer] do
        Process.cancel_timer(state[:timer])
      end

      timer = Process.send_after(self(), :flush, flush_interval)
      Map.merge(state, %{timer: timer})
    end

    defp maybe_send_spans(sender, spans) do
      DynamicSupervisor.start_child(
        Tapper.Reporter.AsyncReporter.WorkerSuper,
        {Task, fn -> Tapper.Reporter.send(sender, spans) end}
      )
    end
  end
end
