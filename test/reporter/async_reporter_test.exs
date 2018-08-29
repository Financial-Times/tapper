defmodule Tapper.Reporter.AsyncReporterTest do
  use ExUnit.Case, async: false

  import Mox

  alias Tapper.Reporter.AsyncReporter

  setup :set_mox_global

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  test "concats spans until flush is called" do
    first_span = "first-span"
    second_span = "second-span"

    MockSender
    |> expect(:ingest, fn [^first_span, ^second_span] -> :ok end)

    AsyncReporter.start_link([], sender: MockSender)
    AsyncReporter.ingest([first_span])
    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    # Let the worker finish
    Process.sleep(10)
  end

  test "reports spans periodically" do
    first_span = "first-span"
    second_span = "second-span"

    MockSender
    |> expect(:ingest, fn [^first_span] -> :ok end)
    |> expect(:ingest, fn [^second_span] -> :ok end)

    AsyncReporter.start_link([], sender: MockSender, flush_interval: 5)

    AsyncReporter.ingest([first_span])
    Process.sleep(10)

    AsyncReporter.ingest([second_span])
    Process.sleep(10)
  end

  test "reports spans when max_spans_threshold is hit" do
    first_span = "first-span"
    second_span = "second-span"

    MockSender
    |> expect(:ingest, fn [^first_span] -> :ok end)
    |> expect(:ingest, fn [^second_span] -> :ok end)

    AsyncReporter.start_link([], sender: MockSender, max_spans_threshold: 1)
    AsyncReporter.ingest([first_span])
    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    # Let the worker finish
    Process.sleep(10)
  end

  test "does not spawn more than max_concurrent_flush_threshold workers" do
    first_span = "first-span"
    second_span = "second-span"
    third_span = "third-span"

    # Third span is ignored because the first two exhausted the max concurrent
    # flush threshold
    MockSender
    |> expect(:ingest, fn [^first_span] -> Process.sleep(10) end)
    |> expect(:ingest, fn [^second_span] -> Process.sleep(10) end)

    AsyncReporter.start_link([], sender: MockSender, max_concurrent_flush_threshold: 2)

    AsyncReporter.ingest([first_span])
    AsyncReporter.flush()

    AsyncReporter.ingest([second_span])
    AsyncReporter.flush()

    AsyncReporter.ingest([third_span])
    AsyncReporter.flush()

    # Let the workers finish
    Process.sleep(20)
  end
end
