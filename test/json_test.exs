defmodule JsonTest do
    use ExUnit.Case

    test "encode with parent_id, no annotations" do
        {trace_id, _uniq} = Tapper.TraceId.generate()
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

        # IO.inspect json

        assert is_list(json)
        assert json == [91,
            [[123,
            [[34, ["traceId"], 34], 58, [34, [Tapper.Id.Utils.to_hex(trace_id)], 34],
                44, [34, ["timestamp"], 34], 58, "1234", 44, [34, ["parentId"], 34], 58,
                [34, [Tapper.SpanId.to_hex(parent_span_id)], 34], 44, [34, ["name"], 34], 58,
                [34, ["test"], 34], 44, [34, ["id"], 34], 58,
                [34, [Tapper.SpanId.to_hex(span_id)], 34], 44, [34, ["duration"], 34], 58, "100", 44,
                [34, ["debug"], 34], 58, "true"], 125]], 
        93]
    end

    test "encode parent_id with root parent_id" do
        map = Tapper.Encoder.Json.encode_parent_id(%{}, %Tapper.Protocol.Span{parent_id: :root})
        assert map == %{}
    end

    test "encode 64-bit trace_id" do
        map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: 1234})
        assert map == %{traceId: "4d2"}
    end

    test "encode 128-bit trace_id" do
        <<trace_id :: size(128)>> = <<0,255,255,255,255,255,255,255,0,255,255,255,255,255,255,255>>

        map = Tapper.Encoder.Json.encode_trace_id(%{}, %Tapper.Protocol.Span{trace_id: trace_id})
        assert map == %{traceId: "ffffffffffffff00ffffffffffffff"}
    end

    test "encode annotation with port" do
        annotation = %Tapper.Protocol.Annotation{
            value: :cs,
            timestamp: 1001,
            host: %Tapper.Protocol.Endpoint{
                service_name: "a-service",
                ipv4: {192,168,1,1},
                port: 8080
            }
        }

        assert %{
            value: :cs,
            timestamp: 1001,
            endpoint: %{
                serviceName: "a-service",
                ipv4: "192.168.1.1",
                port: 8080
            }
        } == Tapper.Encoder.Json.encode_annotation(annotation)
    end

    test "encode annotation, no port" do
        annotation = %Tapper.Protocol.Annotation{
            value: :cs,
            timestamp: 1001,
            host: %Tapper.Protocol.Endpoint{
                service_name: "a-service",
                ipv4: {192,168,1,1}
            }
        }

        assert %{
            value: :cs,
            timestamp: 1001,
            endpoint: %{
                serviceName: "a-service",
                ipv4: "192.168.1.1"
            }
        } == Tapper.Encoder.Json.encode_annotation(annotation)
    end

    test "encode with annotations" do
        {trace_id, _uniq} = Tapper.TraceId.generate()
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
                        ipv4: {10,1,1,100},
                        service_name: "my-service",
                        port: 443
                    }
                },
                %Tapper.Protocol.Annotation{
                    value: :cr,
                    timestamp: 2000,
                    host: %Tapper.Protocol.Endpoint{
                        ipv4: {10,1,1,100},
                        service_name: "my-service",
                        port: 443
                    }
                }
            ]
        }

        json_iolist = Tapper.Encoder.Json.encode!([proto_span])

        assert is_list(json_iolist)

        # IO.inspect(IO.iodata_to_binary(json_iolist))

        json = Poison.decode!(IO.iodata_to_binary(json_iolist))

        assert is_list(json)

        json_annotations = hd(json)["annotations"]
        assert json_annotations
        assert length(json_annotations) == 2

        assert hd(json_annotations)["value"] == "cs"
        assert hd(tl(json_annotations))["value"] == "cr"
    end


    test "encode multiple spans" do
        {trace_id, _uniq} = Tapper.TraceId.generate()
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

        json = Poison.decode!(IO.iodata_to_binary(iolist_json))

        assert [span_1, span_2] = json

        assert span_1["traceId"] == Tapper.TraceId.to_hex({trace_id, 0})
        assert span_1["traceId"] == span_2["traceId"]
        assert span_1["id"] == Tapper.SpanId.to_hex(span_id_1)
        assert span_2["id"] == Tapper.SpanId.to_hex(span_id_2)
        assert span_1["parentId"] == nil
        assert span_2["parentId"] == span_1["id"]
        assert span_1["name"] == "main"
        assert span_2["name"] == "sub"    
    end
end