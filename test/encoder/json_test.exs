defmodule JsonTest do
  use ExUnit.Case

  @json_codec Application.get_env(:tapper, :json_codec, Jason)

  describe "endpoint serviceName encoding" do
    test "serviceName is empty-string should encode as empty-string" do
      assert %{serviceName: ""} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{service_name: ""})
    end

    test "serviceName is \"unknown\" should encode as empty-string" do
      assert %{serviceName: ""} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{
                 service_name: "unknown"
               })
    end

    test "serviceName is :unknown should encode as empty-string" do
      assert %{serviceName: ""} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{
                 service_name: :unknown
               })
    end

    test "serviceName is nil should encode as empty string" do
      assert %{serviceName: ""} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{service_name: nil})
    end

    test "serviceName is non-empty string should encode as non-empty lower-case string" do
      assert %{serviceName: "myservice"} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{
                 service_name: "Myservice"
               })
    end

    test "serviceName is atom, but not nil, should encode as lower-case string" do
      assert %{serviceName: "myservice"} =
               Tapper.Encoder.Json.encode_endpoint(%Tapper.Protocol.Endpoint{
                 service_name: :Myservice
               })
    end
  end

  test "encode with parent_id, no annotations" do
    trace_id = Tapper.TraceId.generate()
    span_id = Tapper.SpanId.generate()
    parent_span_id = Tapper.SpanId.generate()

    proto_span = %Tapper.Protocol.Span{
      trace_id: trace_id,
      id: span_id,
      parent_id: parent_span_id,
      name: "test",
      timestamp: 1234,
      duration: 100,
      debug: true
    }

    json = Tapper.Encoder.Json.encode!([proto_span])

    assert is_list(json)
    assert [91 | _] = json, "iodata starting with ["
    assert [93 | _] = Enum.reverse(json), "iodata ending with ]"

    assert @json_codec.decode!(json) == [
      %{
        "traceId" => Tapper.Id.Utils.to_hex(trace_id),
        "timestamp" => 1234,
        "parentId" => Tapper.SpanId.to_hex(parent_span_id),
        "name" => "test",
        "id" => Tapper.SpanId.to_hex(span_id),
        "duration" => 100,
        "debug" => true
      }
    ]
  end

  test "encode parent_id with root parent_id" do
    map = Tapper.Encoder.Json.encode_parent_id(%{}, %Tapper.Protocol.Span{parent_id: :root})
    assert map == %{}
  end

  test "encode 64-bit trace_id" do
    {:ok, trace_id} = Tapper.TraceId.parse("00ffffffffffffff")

    map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: trace_id})
    assert map == %{traceId: "00ffffffffffffff"}
  end

  test "encode 128-bit trace_id" do
    {:ok, trace_id} = Tapper.TraceId.parse("00ffffffffffffff00ffffffffffffff")

    map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: trace_id})
    assert map == %{traceId: "00ffffffffffffff00ffffffffffffff"}
  end

  test "encode with annotations" do
    trace_id = Tapper.TraceId.generate()
    span_id = Tapper.SpanId.generate()
    parent_span_id = Tapper.SpanId.generate()

    proto_span = %Tapper.Protocol.Span{
      trace_id: trace_id,
      id: span_id,
      parent_id: parent_span_id,
      name: "test",
      timestamp: 1234,
      duration: 100,
      debug: true,
      annotations: [
        %Tapper.Protocol.Annotation{
          value: :cs,
          timestamp: 1000,
          host: %Tapper.Protocol.Endpoint{
            ipv4: {10, 1, 1, 100},
            service_name: "my-service",
            port: 443
          }
        },
        %Tapper.Protocol.Annotation{
          value: :cr,
          timestamp: 2000,
          host: %Tapper.Protocol.Endpoint{
            ipv4: {10, 1, 1, 100},
            service_name: "my-service",
            port: 443
          }
        }
      ],
      binary_annotations: [
        %Tapper.Protocol.BinaryAnnotation{
          annotation_type: :bool,
          key: "sa",
          value: true,
          host: %Tapper.Protocol.Endpoint{
            ipv6: {1, 0, 0, 4, 5, 6, 7, 8},
            service_name: "my-service",
            port: 8443
          }
        },
        %Tapper.Protocol.BinaryAnnotation{
          annotation_type: :string,
          key: "http.path",
          value: "/foo/bar",
          host: %Tapper.Protocol.Endpoint{
            ipv4: {10, 1, 1, 100},
            service_name: "my-server",
            port: 443
          }
        }
      ]
    }

    json_iolist = Tapper.Encoder.Json.encode!([proto_span])

    assert is_list(json_iolist)

    json = @json_codec.decode!(IO.iodata_to_binary(json_iolist))

    assert is_list(json)

    json_annotations = hd(json)["annotations"]
    assert json_annotations
    assert length(json_annotations) == 2

    assert hd(json_annotations)["value"] == "cs"
    assert hd(tl(json_annotations))["value"] == "cr"
    assert hd(tl(json_annotations))["endpoint"]["ipv4"] == "10.1.1.100"
    assert hd(tl(json_annotations))["endpoint"]["ipv6"] == nil

    json_binary_annotations = hd(json)["binaryAnnotations"]
    assert json_binary_annotations
    assert length(json_binary_annotations) == 2

    assert hd(json_binary_annotations)["type"] == "BOOL"
    assert hd(json_binary_annotations)["key"] == "sa"
    assert hd(json_binary_annotations)["value"] == true
    assert hd(json_binary_annotations)["endpoint"]["serviceName"] == "my-service"
    assert hd(json_binary_annotations)["endpoint"]["ipv4"] == nil
    assert hd(json_binary_annotations)["endpoint"]["ipv6"] == "1::4:5:6:7:8"

    assert hd(tl(json_binary_annotations))["type"] == nil
    assert hd(tl(json_binary_annotations))["key"] == "http.path"
    assert hd(tl(json_binary_annotations))["value"] == "/foo/bar"
    assert hd(tl(json_binary_annotations))["endpoint"]["serviceName"] == "my-server"
  end

  test "encode multiple spans" do
    trace_id = Tapper.TraceId.generate()
    span_id_1 = Tapper.SpanId.generate()
    span_id_2 = Tapper.SpanId.generate()

    spans = [
      %Tapper.Protocol.Span{
        trace_id: trace_id,
        id: span_id_1,
        parent_id: :root,
        name: "main",
        timestamp: 1000,
        duration: 4000,
        debug: true
      },
      %Tapper.Protocol.Span{
        trace_id: trace_id,
        id: span_id_2,
        parent_id: span_id_1,
        name: "sub",
        timestamp: 2000,
        duration: 1000,
        debug: true
      }
    ]

    iolist_json = Tapper.Encoder.Json.encode!(spans)

    json = @json_codec.decode!(IO.iodata_to_binary(iolist_json))

    assert [span_1, span_2] = json

    assert span_1["traceId"] == Tapper.TraceId.to_hex(trace_id)
    assert span_1["traceId"] == span_2["traceId"]
    assert span_1["id"] == Tapper.SpanId.to_hex(span_id_1)
    assert span_2["id"] == Tapper.SpanId.to_hex(span_id_2)
    assert span_1["parentId"] == nil
    assert span_2["parentId"] == span_1["id"]
    assert span_1["name"] == "main"
    assert span_2["name"] == "sub"
  end
end
