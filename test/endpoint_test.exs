defmodule EndpointTest do
  use ExUnit.Case
  doctest Tapper.TraceId

  alias Tapper.Endpoint

  test "host_ip returns IPV4 or IPV6 tuple" do
    ip = Endpoint.host_ip()

    assert is_tuple(ip)
    assert tuple_size(ip) in [4, 8]
  end

end
