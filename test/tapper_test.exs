defmodule TapperTest do
  use ExUnit.Case
  doctest Tapper

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
    |> Tapper.annotate(:wr, %Tapper.Endpoint{service_name: "proto", ipv4: {1, 2, 3, 4}})
    |> Tapper.binary_annotate(:i16, "units", 233)

    id = Tapper.finish_span(id)

    :ok = Tapper.finish(id)

    assert_receive {^ref, spans}, 1_000
    assert is_list(spans)
    assert length(spans) == 3

    main_span = Enum.find(spans, fn(span) -> span.name == "main" end)
    child_1 = Enum.find(spans, fn(span) -> span.name == "child-1" end)
    child_2 = Enum.find(spans, fn(span) -> span.name == "child-2" end)

    assert length(main_span.annotations) == 1

    assert length(child_1.annotations) == 0
    assert length(child_1.binary_annotations) == 8

    assert length(child_2.annotations) == 2
    assert length(child_2.binary_annotations) == 2
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

    main_span = Enum.find(spans, fn(span) -> span.name == "main" end)
    assert main_span.id == span_id
    assert main_span.trace_id == elem(trace_id, 0)
    assert main_span.parent_id == parent_span_id

    assert hd(main_span.binary_annotations).key == :ca
  end
end
