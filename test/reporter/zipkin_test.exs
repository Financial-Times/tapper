defmodule ZipkinTest do

  use ExUnit.Case

  test "encodes spans using Json encoder" do
    trace_id = Tapper.TraceId.generate()

    annotations = []
    binary_annotations = []

    span = %Tapper.Protocol.Span{
      trace_id: trace_id,
      id: Tapper.SpanId.generate(),
      name: "test",
      parent_id: Tapper.SpanId.generate(),
      debug: true,
      timestamp: 1,
      duration: 100,
      annotations: annotations,
      binary_annotations: binary_annotations
    }

    processed = Tapper.Reporter.Zipkin.process_request_body([span])

    assert processed == Tapper.Encoder.Json.encode!([span])
  end

  test "adds content-type header" do
    headers = Tapper.Reporter.Zipkin.process_request_headers([])

    assert headers == [{"Content-Type", "application/json"}]
  end

  test "adds hackney options" do
    Application.put_env(:tapper, Tapper.Reporter.Zipkin, client_opts: [a: 1, b: 2])

    options = Tapper.Reporter.Zipkin.process_request_options(foo: :bar)

    assert a: 1 in options
    assert b: 2 in options
    assert foo: :bar in options
  end

  test "url from config" do
    Application.put_env(:tapper, Tapper.Reporter.Zipkin, collector_url: "http://localhost/spans")

    assert Tapper.Reporter.Zipkin.url() == "http://localhost/spans"

    Application.delete_env(:tapper, Tapper.Reporter.Zipkin)

    assert_raise ArgumentError, fn -> Tapper.Reporter.Zipkin.url() end

    Application.put_env(:tapper, Tapper.Reporter.Zipkin, test: "test")

    assert_raise ArgumentError, fn -> Tapper.Reporter.Zipkin.url() end
  end

end
