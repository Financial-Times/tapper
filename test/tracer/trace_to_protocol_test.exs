defmodule Tracer.TraceToProtocolTest do

  use ExUnit.Case

  alias Tapper.Protocol
  alias Tapper.Tracer.Trace.Convert
  alias Tapper.Tracer.Trace
  alias Tapper.Timestamp

  import Test.Helper.Server
  import Test.Helper.Protocol

  describe "to_protocol_endpoint/1" do

    test "ipv4 endpoint is copied to ipv4 field" do
      ip = {10, 0, 0, 1}
      endpoint = %Tapper.Endpoint{
        ip: ip
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{ipv4: ^ip} = protocol_endpoint
    end

    test "ipv6 endpoint is copied to ipv6 field" do
      ip = {10, 0, 0, 1, 1, 2, 3, 4}
      endpoint = %Tapper.Endpoint{
        ip: ip
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{ipv6: ^ip} = protocol_endpoint
    end

    test "missing ip sets fields to nil" do
      endpoint = %Tapper.Endpoint{
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{ipv4: nil, ipv6: nil} = protocol_endpoint
    end

    test "service_name is copied" do
      endpoint = %Tapper.Endpoint{
        service_name: "service-svc"
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{service_name: "service-svc"} = protocol_endpoint
    end

    test "missing service_name defaults to unknown" do
      endpoint = %Tapper.Endpoint{
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{service_name: "unknown"} = protocol_endpoint
    end


    test "missing service_name becomes hostname if set" do
      endpoint = %Tapper.Endpoint{
        hostname: "my-service.ft.com"
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{service_name: "my-service.ft.com"} = protocol_endpoint
    end

    test "port copies" do
      endpoint = %Tapper.Endpoint{
        port: 9876
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{port: 9876} = protocol_endpoint
    end

    test "missing port defaults to 0" do
      endpoint = %Tapper.Endpoint{
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{port: 0} = protocol_endpoint
    end

    test "nil endpoint converts to nil" do
      assert Convert.to_protocol_endpoint(nil) == nil
    end

    test "hostname with ipv4 resolution sets ipv4 field" do
      endpoint = %Tapper.Endpoint{
        hostname: :inet
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{ipv4: {10, 1, 1, 10}} = protocol_endpoint
    end
    test "hostname with ipv6 resolution sets ipv6 field" do
            endpoint = %Tapper.Endpoint{
        hostname: :inet6
      }

      protocol_endpoint = Convert.to_protocol_endpoint(endpoint)

      assert %Protocol.Endpoint{ipv6: {1111, 1, 1, 1, 1, 1, 1, 1111}} = protocol_endpoint
    end

  end

  describe "to_protocol_annotation/1" do

    test "with endpoint" do
      endpoint = random_endpoint()

      annotation = %Trace.Annotation{
        timestamp: Tapper.Timestamp.instant(),
        host: endpoint,
        value: "Test"
      }

      protocol_annotation = Convert.to_protocol_annotation(annotation)

      absolute_timestamp = Timestamp.to_absolute(annotation.timestamp)

      assert %Protocol.Annotation{
        timestamp: ^absolute_timestamp,
        value: "Test"
      } = protocol_annotation

      assert protocol_annotation.host == Convert.to_protocol_endpoint(endpoint)
    end

    test "without endpoint" do
      annotation = %Trace.Annotation{
        timestamp: Tapper.Timestamp.instant(),
        value: "Test"
      }

      protocol_annotation = Convert.to_protocol_annotation(annotation)

      absolute_timestamp = Timestamp.to_absolute(annotation.timestamp)

      assert %Protocol.Annotation{
        timestamp: ^absolute_timestamp,
        value: "Test"
      } = protocol_annotation

      assert protocol_annotation.host == nil
    end


  end

  describe "to_protocol_binary_annotation/1" do
    test "with endpoint" do
      endpoint = random_endpoint()

      annotation = %Trace.BinaryAnnotation{
        host: endpoint,
        annotation_type: :string,
        key: "Foo",
        value: "Test"
      }

      protocol_annotation = Convert.to_protocol_binary_annotation(annotation)

      assert %Protocol.BinaryAnnotation{key: "Foo", value: "Test", annotation_type: :string} = protocol_annotation

      assert protocol_annotation.host == Convert.to_protocol_endpoint(endpoint)
    end

    test "without endpoint" do
      annotation = %Trace.BinaryAnnotation{
        annotation_type: :string,
        key: "Foo",
        value: "Test"
      }

      protocol_annotation = Convert.to_protocol_binary_annotation(annotation)

      assert %Protocol.BinaryAnnotation{key: "Foo", value: "Test", annotation_type: :string} = protocol_annotation

      assert protocol_annotation.host == nil
    end

  end

  describe "to_protocol_span/2" do
    test "converts timestamp to absolute value" do
      timestamp = Timestamp.instant()

      trace_span = span(1, timestamp, 1000)

      trace = trace([trace_span])

      protocol_span = Convert.to_protocol_span(trace_span, trace)

      assert protocol_span.timestamp === Timestamp.to_absolute(trace_span.start_timestamp)
    end

    test "sets duration" do
      timestamp = Timestamp.instant()

      trace_span = span(1, timestamp, 1000)

      trace = trace([trace_span])

      protocol_span = Convert.to_protocol_span(trace_span, trace)

      assert_in_delta protocol_span.duration, Timestamp.duration(trace_span.start_timestamp, trace_span.end_timestamp), 2
    end

    test "sets duration in span with missing end_timestamp to trace end_timestamp" do
      timestamp = Timestamp.instant()

      trace_span = %{span(1, timestamp, 1000) | end_timestamp: nil}

      trace = trace([trace_span])

      protocol_span = Convert.to_protocol_span(trace_span, trace)

      assert_in_delta protocol_span.duration, Timestamp.duration(trace_span.start_timestamp, trace.end_timestamp), 2
    end

    test "converts annotations" do
      timestamp = Timestamp.instant()

      annotation_1 = Tapper.Tracer.Annotations.annotation(:foo, Timestamp.incr(timestamp, 500), random_endpoint())
      annotation_2 = Tapper.Tracer.Annotations.annotation(:bar, Timestamp.incr(timestamp, 700), random_endpoint())

      trace_span = %{span(1, timestamp, 1000) | annotations: [annotation_1, annotation_2]}

      trace = trace([trace_span])

      protocol_span = Convert.to_protocol_span(trace_span, trace)

      assert length(protocol_span.annotations) === 2
      assert length(protocol_span.binary_annotations) === 0

      protocol_annotation_1 = protocol_annotation_by_value(protocol_span.annotations, :foo)
      assert protocol_annotation_1 == %Protocol.Annotation{value: :foo, timestamp: Timestamp.to_absolute(annotation_1.timestamp), host: Convert.to_protocol_endpoint(annotation_1.host)}

      protocol_annotation_2 = protocol_annotation_by_value(protocol_span.annotations, :bar)
      assert protocol_annotation_2 == %Protocol.Annotation{value: :bar, timestamp: Timestamp.to_absolute(annotation_2.timestamp), host: Convert.to_protocol_endpoint(annotation_2.host)}
    end

    test "converts binary annotations" do
      timestamp = Timestamp.instant()

      annotation_1 = Tapper.Tracer.Annotations.binary_annotation(:ca, random_endpoint())
      annotation_2 = Tapper.Tracer.Annotations.binary_annotation(:string, "foo", "bar", random_endpoint())

      trace_span = %{span(1, timestamp, 1000) | binary_annotations: [annotation_1, annotation_2]}

      trace = trace([trace_span])

      protocol_span = Convert.to_protocol_span(trace_span, trace)

      assert length(protocol_span.binary_annotations) === 2
      assert length(protocol_span.annotations) === 0

      protocol_annotation_1 = protocol_binary_annotation_by_key(protocol_span.binary_annotations, :ca)
      assert protocol_annotation_1 == %Protocol.BinaryAnnotation{annotation_type: :bool, key: :ca, value: true, host: Convert.to_protocol_endpoint(annotation_1.host)}

      protocol_annotation_2 = protocol_binary_annotation_by_key(protocol_span.binary_annotations, "foo")
      assert protocol_annotation_2 == %Protocol.BinaryAnnotation{annotation_type: :string, key: "foo", value: "bar", host: Convert.to_protocol_endpoint(annotation_2.host)}
    end

  end

  describe "to_protocol_spans/1" do
      timestamp = Timestamp.instant()

      trace_spans = [span(1, timestamp, 1000), span(2, Timestamp.incr(timestamp, 100), 1000)]

      trace = trace(trace_spans)

      protocol_spans = Convert.to_protocol_spans(trace)

      assert length(protocol_spans) === 2
      assert protocol_span_by_name(protocol_spans, "span_1")
      assert protocol_span_by_name(protocol_spans, "span_2")
  end

end
