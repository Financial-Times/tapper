defmodule JsonAnnotationsTest do
  use ExUnit.Case

  test "encode annotation with port" do
    annotation = %Tapper.Protocol.Annotation{
      value: :cs,
      timestamp: 1001,
      host: %Tapper.Protocol.Endpoint{
        service_name: "a-service",
        ipv4: {192, 168, 1, 1},
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
        ipv4: {192, 168, 1, 1}
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

  test "encode binary annotation type" do
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :string) == %{}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :bool) == %{type: "BOOL"}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :i16) == %{type: "I16"}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :i32) == %{type: "I32"}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :i64) == %{type: "I64"}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :double) == %{type: "DOUBLE"}
    assert Tapper.Encoder.Json.encode_binary_annotation_type(%{}, :bytes) == %{type: "BYTES"}
  end

  test "encode binary annotation value" do
    assert Tapper.Encoder.Json.encode_binary_annotation_value(:string, "a string") == "a string"
    assert Tapper.Encoder.Json.encode_binary_annotation_value(:bool, true) == true
    assert Tapper.Encoder.Json.encode_binary_annotation_value(:bool, false) == false

    assert Tapper.Encoder.Json.encode_binary_annotation_value(:i16, 32_767) == 32_767

    assert_raise ArgumentError, fn ->
      Tapper.Encoder.Json.encode_binary_annotation_value(:i16, 32_768)
    end

    assert Tapper.Encoder.Json.encode_binary_annotation_value(:i32, 4_294_967_295) ==
             4_294_967_295

    assert_raise ArgumentError, fn ->
      Tapper.Encoder.Json.encode_binary_annotation_value(:i32, 4_294_967_296)
    end

    assert Tapper.Encoder.Json.encode_binary_annotation_value(:i64, 9_007_199_254_740_991) ==
             9_007_199_254_740_991

    assert Tapper.Encoder.Json.encode_binary_annotation_value(:i64, 9_007_199_254_740_992) ==
             "9007199254740992"

    assert_raise ArgumentError, fn ->
      Tapper.Encoder.Json.encode_binary_annotation_value(:i64, 1.8_446_744_073_709_552e19)
    end

    assert Tapper.Encoder.Json.encode_binary_annotation_value(:bytes, <<1, 2, 3, 4>>) ==
             Base.encode64(<<1, 2, 3, 4>>)
  end

  test "encode binary annotation" do
    host = %Tapper.Protocol.Endpoint{
      ipv4: {10, 1, 1, 100},
      service_name: "my-service",
      port: 443
    }

    endpoint = %{serviceName: "my-service", ipv4: "10.1.1.100", port: 443}

    as_string =
      Tapper.Encoder.Json.encode_binary_annotation(%Tapper.Protocol.BinaryAnnotation{
        annotation_type: :string,
        key: "key_for_string",
        value: "string-value",
        host: host
      })

    assert as_string == %{key: "key_for_string", value: "string-value", endpoint: endpoint}

    as_i16 =
      Tapper.Encoder.Json.encode_binary_annotation(%Tapper.Protocol.BinaryAnnotation{
        annotation_type: :i16,
        key: "key_for_i16",
        value: 1024,
        host: host
      })

    assert as_i16 == %{key: "key_for_i16", value: 1024, type: "I16", endpoint: endpoint}
  end
end
