defmodule EndpointTest do
  use ExUnit.Case
  doctest Tapper.TraceId

  alias Tapper.Endpoint

  test "host_ip returns IPV4 or IPV6 tuple" do
    ip = Endpoint.host_ip()

    assert is_tuple(ip)
    assert tuple_size(ip) in [4, 8]
  end

  test "apply_hostent/2 with resolved ipv4 updates ip with IPV4 tuple" do
    endpoint = %Endpoint{service_name: "search", hostname: "google.com", port: 80}
    hostent = {:ok, {:hostent, 'google.com', [], :inet, 4, [{216, 58, 214, 14}]}}
    updated = Endpoint.apply_hostent(endpoint, hostent)
    assert updated.ip == {216, 58, 214, 14}
  end

  test "apply_hostent/2 with resolved ipv6 updates ip with IPV6 tuple" do
    endpoint = %Endpoint{service_name: "search", hostname: "google.com", port: 80}

    hostent =
      {:ok, {:hostent, 'google.com', [], :inet6, 16, [{10_752, 5200, 16_393, 2067, 0, 0, 0, 8206}]}}

    updated = Endpoint.apply_hostent(endpoint, hostent)
    assert updated.ip == {10_752, 5200, 16_393, 2067, 0, 0, 0, 8206}
  end

  test "apply_hostent/2 with resolve error is identity" do
    endpoint = %Endpoint{service_name: "search", hostname: "google.com", port: 80}
    hostent = {:error, :nxdomain}
    assert endpoint == Endpoint.apply_hostent(endpoint, hostent)
  end

  test "resolve/1 endpoint with ipv4 resolution updates ip, retains hostname" do
    # NB exercises test gethostbyname/1
    assert Endpoint.resolve(%Endpoint{hostname: :inet}) == %Endpoint{
             ip: {10, 1, 1, 10},
             hostname: :inet
           }
  end

  test "resolve/1 endpoint with ipv6 resolution updates ip, retains hostname" do
    # NB exercises test gethostbyname/1
    assert Endpoint.resolve(%Endpoint{hostname: :inet6}) == %Endpoint{
             ip: {1111, 1, 1, 1, 1, 1, 1, 1111},
             hostname: :inet6
           }
  end
end
