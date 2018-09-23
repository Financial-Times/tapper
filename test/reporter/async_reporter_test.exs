defmodule Tapper.Reporter.AsyncReporterTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Tapper.Reporter.AsyncReporter

  test "concats spans until flush is called" do
    first_span = "first-span"
    second_span = "second-span"

    {ref, sender} = Test.Helper.Server.msg_reporter()

    start_supervised!({AsyncReporter, sender: sender})
    AsyncReporter.ingest([first_span])
    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    assert_receive {^ref, [^first_span, ^second_span]}
  end

  test "reports spans periodically" do
    first_span = "first-span"
    second_span = "second-span"

    {ref, sender} = Test.Helper.Server.msg_reporter()

    start_supervised!({AsyncReporter, sender: sender, flush_interval: 5})

    AsyncReporter.ingest([first_span])
    AsyncReporter.ingest([second_span])

    assert_receive {^ref, [^first_span, ^second_span]}
  end

  test "reports spans when max_spans_threshold is hit" do
    first_span = "first-span"
    second_span = "second-span"

    {ref, sender} = Test.Helper.Server.msg_reporter()

    start_supervised!({AsyncReporter, sender: sender, max_spans_threshold: 1})

    AsyncReporter.ingest([first_span])
    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    assert_receive {^ref, [^first_span]}
    assert_receive {^ref, [^second_span]}
  end

  test "does not spawn more than max_concurrent_flush_threshold workers" do
    first_span = "first-span"
    second_span = "second-span"
    third_span = "third-span"

    {ref, sender} = Test.Helper.Server.msg_reporter()

    sender = fn spans ->
      Process.sleep(50)
      sender.(spans)
    end

    # Third span is ignored because the first two exhausted the max concurrent
    # flush threshold
    start_supervised!({AsyncReporter, sender: sender, max_concurrent_flush_threshold: 2})

    AsyncReporter.ingest([first_span])
    AsyncReporter.flush()

    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    AsyncReporter.ingest([third_span])

    log =
      capture_log(fn ->
        AsyncReporter.flush()
      end)

    assert_receive {^ref, [^first_span]}
    assert_receive {^ref, [^second_span]}

    refute_receive {^ref, _}, 200

    assert log =~ "Maximum sender concurrency reached"
  end

  describe "reporter configuration" do
    test "uses a reporter specified as module" do
      defmodule TestSender do
        @behaviour Tapper.Reporter.Api
        def ingest(spans) do
          send(Tapper.Reporter.AsyncReporterTest, spans)
        end
      end

      start_supervised!({AsyncReporter, sender: TestSender})
      Process.register(self(), Tapper.Reporter.AsyncReporterTest)

      first_span = "first-span"
      second_span = "second-span"

      AsyncReporter.ingest([first_span])
      AsyncReporter.ingest([second_span])

      refute_receive _

      AsyncReporter.flush()

      assert_receive [first_span, second_span]
    end

    test "supervises a reporter specified as {module, args}" do
      defmodule TestSenderServer do
        use Agent

        def start_link(_) do
          Agent.start_link(fn -> [] end, name: __MODULE__)
        end

        @behaviour Tapper.Reporter.Api
        def ingest(spans) do
          Agent.update(__MODULE__, &(&1 ++ spans))
        end

        def get() do
          Agent.get(__MODULE__, & &1)
        end
      end

      start_supervised!({AsyncReporter, sender: {TestSenderServer, []}})

      first_span = "first-span"
      second_span = "second-span"

      AsyncReporter.ingest([first_span])
      AsyncReporter.ingest([second_span])

      assert TestSenderServer.get() == []

      AsyncReporter.flush()

      assert TestSenderServer.get() == [first_span, second_span]
    end

    test "rejects a reporter that does not implement Tapper.Reporter.Api" do
      defmodule BadSender do
        def ingest(_) do
          :ok
        end
      end

      assert {:error, _} = start_supervised({AsyncReporter, sender: BadSender})
    end
  end
end
