defmodule ZipkinTest do

  use ExUnit.Case

  test "encodes spans using Json encoder" do
    {trace_id, _} = Tapper.TraceId.generate()

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
    options = Tapper.Reporter.Zipkin.process_request_options([foo: :bar])

    assert hackney: [pool: :tapper] in options
  end

end