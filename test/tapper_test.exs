defmodule TapperTest do
  @moduledoc "These are the integration tests, testing from the API-level using a real Tapper server."

  use ExUnit.Case
  doctest Tapper

  import Test.Helper.Protocol

  test "start api" do
    {ref, reporter} = Test.Helper.Server.msg_reporter()

    id = Tapper.start(name: "main", sample: true, reporter: reporter)

    id = Tapper.start_span(id, name: "child-1")

    id
    |> Tapper.http_host("api.ft.com")
    |> Tapper.http_path("my/api")
    |> Tapper.http_method("PUT")
    |> Tapper.http_url("https://api.ft.com/my/api?foo=bar")
    |> Tapper.http_request_size(100)
    |> Tapper.http_status_code(201)
    |> Tapper.http_response_size(1024)
    |> Tapper.tag("cpu_temperature", 78.3)

    id = Tapper.finish_span(id)

    id = Tapper.start_span(id, name: "child-2", local: "local-algorithm")

    id
    |> Tapper.annotate(:ws)
    |> Tapper.annotate(:wr, %Tapper.Endpoint{service_name: "proto", ip: {1, 2, 3, 4}})
    |> Tapper.binary_annotate(:i16, "units", 233)

    id = Tapper.finish_span(id)

    :ok = Tapper.finish(id)

    assert_receive {^ref, spans}, 1_000
    assert is_list(spans)
    assert length(spans) == 3

    main_span = protocol_span_by_name(spans, "main")
    child_1 = protocol_span_by_name(spans, "child-1")
    child_2 = protocol_span_by_name(spans, "child-2")

    assert length(main_span.annotations) == 1

    assert length(child_1.annotations) == 0
    assert length(child_1.binary_annotations) == 8
    assert protocol_binary_annotation_by_key(child_1, "http.host").value == "api.ft.com"
    assert protocol_binary_annotation_by_key(child_1, "http.path").value == "my/api"
    assert protocol_binary_annotation_by_key(child_1, "http.method").value == "PUT"
    assert protocol_binary_annotation_by_key(child_1, "http.url").value == "https://api.ft.com/my/api?foo=bar"
    assert protocol_binary_annotation_by_key(child_1, "http.request.size").value == 100
    assert protocol_binary_annotation_by_key(child_1, "http.response.size").value == 1024
    assert protocol_binary_annotation_by_key(child_1, "cpu_temperature").value == 78.3

    assert length(child_2.annotations) == 2
    assert protocol_annotation_by_value(child_2, :ws)
    assert protocol_annotation_by_value(child_2, :wr)
    assert protocol_annotation_by_value(child_2, :wr).host.service_name == "proto"

    assert length(child_2.binary_annotations) == 2
    assert protocol_binary_annotation_by_key(child_2, :lc).value == "local-algorithm"
    assert protocol_binary_annotation_by_key(child_2, "units").value == 233
  end

  test "join api" do
    {ref, reporter} = Test.Helper.Server.msg_reporter()
    trace_id = Tapper.TraceId.generate()
    span_id = Tapper.SpanId.generate()
    parent_span_id = Tapper.SpanId.generate()
    remote_endpoint = Test.Helper.Server.random_endpoint()

    id = Tapper.join(trace_id, span_id, parent_span_id, true, false, name: "main", remote: remote_endpoint, reporter: reporter)

    id = Tapper.start_span(id, name: "child-1")
    id = Tapper.finish_span(id)

    :ok = Tapper.finish(id)

    assert_receive {^ref, spans}, 1_000
    assert is_list(spans)
    assert length(spans) == 2

    main_span = protocol_span_by_name(spans, "main")
    assert main_span.id == span_id
    assert main_span.trace_id == elem(trace_id, 0)
    assert main_span.parent_id == parent_span_id

    assert protocol_binary_annotation_by_key(main_span, :ca)
  end

  test "parallel spans, with syncronous finish add up" do
    {ref, reporter} = Test.Helper.Server.msg_reporter()
    id = Tapper.start(name: "main", sample: true, reporter: reporter)

    id_1 = Tapper.start_span(id, name: "child-1")
    t1 = Task.async(fn ->
        Tapper.tag(id_1, "task", 1)
        Process.sleep(300)
        Tapper.finish_span(id_1)
      end)

    id_2 = Tapper.start_span(id, name: "child-2")
    t2 = Task.async(fn ->
        Tapper.tag(id_2, "task", 2)
        Process.sleep(200)
        Tapper.finish_span(id_2)
      end)

    [{^t1, {:ok, _}}, {^t2, {:ok, _}}] = Task.yield_many([t1,t2], 500)

    Tapper.finish(id)

    assert_receive {^ref, spans}, 1000

    assert length(spans) == 3

    main = protocol_span_by_name(spans, "main")
    child_1 = protocol_span_by_name(spans, "child-1")
    child_2 = protocol_span_by_name(spans, "child-2")

    assert child_1.parent_id == main.id
    assert child_2.parent_id == main.id
    assert child_1.id != main.id
    assert child_2.id != main.id

    assert main.timestamp <= child_1.timestamp
    assert main.timestamp <= child_2.timestamp
    assert child_1.timestamp <= child_2.timestamp

    assert main.duration > 0
    assert child_1.duration > 0
    assert child_2.duration > 0

    assert child_1.duration <= main.duration
    assert child_2.duration <= main.duration

    assert main.timestamp + main.duration >= child_1.timestamp + child_1.duration, "Main span's duration should be >= all child spans"
    assert main.timestamp + main.duration >= child_2.timestamp + child_2.duration, "Main span's duration should be >= all child spans"

    assert child_1.duration > child_2.duration
    assert child_1.duration >= 300_000 # 300ms == 300,000µs
    assert child_2.duration >= 200_000
  end

  test "parallel spans, with asyncronous finish add up" do
    {ref, reporter} = Test.Helper.Server.msg_reporter()
    id = Tapper.start(name: "main", sample: true, reporter: reporter, ttl: 400)

    id_1 = Tapper.start_span(id, name: "child-1")
    t1 = Task.async(fn ->
        Tapper.tag(id_1, "task", 1)
        Process.sleep(300)
        Tapper.finish_span(id_1)
      end)

    id_2 = Tapper.start_span(id, name: "child-2")
    t2 = Task.async(fn ->
        Tapper.tag(id_2, "task", 2)
        Process.sleep(50)
        Tapper.finish_span(id_2)
      end)

    Tapper.finish(id, async: true)

    [{^t1, {:ok, _}}, {^t2, {:ok, _}}] = Task.yield_many([t1,t2], 400)

    assert_receive {^ref, spans}, 600

    assert length(spans) == 3

    main = protocol_span_by_name(spans, "main")
    child_1 = protocol_span_by_name(spans, "child-1")
    child_2 = protocol_span_by_name(spans, "child-2")

    assert child_1.parent_id == main.id
    assert child_2.parent_id == main.id
    assert child_1.id != main.id
    assert child_2.id != main.id

    assert main.timestamp <= child_1.timestamp
    assert main.timestamp <= child_2.timestamp
    assert child_1.timestamp <= child_2.timestamp

    assert main.duration > 0
    assert child_1.duration > 0
    assert child_2.duration > 0

    assert child_1.duration <= main.duration
    assert child_2.duration <= main.duration

    # beware rounding in time calculations
    assert_in_delta main.timestamp + main.duration, child_1.timestamp + child_1.duration, 2, "Last span to finish should set main span's' duration"
    assert main.timestamp + main.duration >= child_2.timestamp + child_2.duration, "Main span's duration should be >= all child spans"

    assert child_1.duration > child_2.duration
    assert child_1.duration >= 300_000 # 300ms == 300,000µs
    assert child_2.duration >= 50_000

    refute protocol_annotation_by_value(main, :timeout), "unexpected :timeout annotation on main span"
    refute protocol_annotation_by_value(child_1, :timeout), "unexpected :timeout annotation"
    refute protocol_annotation_by_value(child_2, :timeout), "unexpected :timeout annotation"

    assert protocol_annotation_by_value(main, :async), "expected main span to have async annotation"

    refute protocol_annotation_by_value(child_1, :async), "unexpected async annotation on child_1"
    refute protocol_annotation_by_value(child_2, :async), "unexpected async annotation on child_2"
  end

  test "parallel spans, with asyncronous time-out add up" do
    {ref, reporter} = Test.Helper.Server.msg_reporter()
    id = Tapper.start(name: "main", sample: true, reporter: reporter, ttl: 100)

    id_1 = Tapper.start_span(id, name: "child-1")
    t1 = Task.async(fn ->
        Tapper.tag(id_1, "task", 1)
        Process.sleep(300)
        Tapper.finish_span(id_1)
      end)

    id_2 = Tapper.start_span(id, name: "child-2")
    t2 = Task.async(fn ->
        Tapper.tag(id_2, "task", 2)
        Tapper.async(id_2)
        Process.sleep(50)
        Tapper.finish_span(id_2)
      end)

    Tapper.finish(id, async: true)

    # we should receive spans due to time-out, before tasks have finished
    assert_receive {^ref, spans}, 200


    [{^t1, {:ok, _}}, {^t2, {:ok, _}}] = Task.yield_many([t1,t2], 400)


    assert length(spans) == 3

    main = protocol_span_by_name(spans, "main")
    child_1 = protocol_span_by_name(spans, "child-1")
    child_2 = protocol_span_by_name(spans, "child-2")

    assert child_1.parent_id == main.id
    assert child_2.parent_id == main.id
    assert child_1.id != main.id
    assert child_2.id != main.id

    assert protocol_annotation_by_value(child_1, :timeout), "expected :timeout annotation on unfinished span"
    refute protocol_annotation_by_value(child_2, :timeout), "unexpected :timeout annotation"

    assert protocol_annotation_by_value(main, :async), "expected main span to have async annotation"
    assert protocol_annotation_by_value(child_2, :async), "expected child_2 span to have async annotation"

    assert main.timestamp <= child_1.timestamp
    assert main.timestamp <= child_2.timestamp
    assert child_1.timestamp <= child_2.timestamp

    assert main.duration > 0
    assert child_1.duration > 0
    assert child_2.duration > 0

    assert child_1.duration <= main.duration
    assert child_2.duration <= main.duration

    # beware rounding in time unit conversion!
    assert_in_delta main.timestamp + main.duration, child_1.timestamp + child_1.duration, 2,
      "main span and unfinished spans should have same end time"

    assert main.timestamp + main.duration > child_2.timestamp + child_2.duration,
      "main span's duration should be > finished child spans"

    assert child_1.duration > child_2.duration
    assert child_1.duration < 300_000, "Unterminated child_1 span should have duration less than sleep time"
    assert child_1.duration >= 100_000, "Unterminated child_1 span should have duration >= the TTL time #{child_1.duration}"

    assert child_2.duration >= 50_000, "child_2 span should have a duration greater than its sleep time"
  end

end
