defmodule Tapper.Endpoint do
  @moduledoc """
  Endpoint description struct; used everywhere an endpoint is required.

  ## Example
  ```
  endpoint = %Endpoint{
    ip: {192, 168, 10, 100},
    service_name: "my-service",
    port: 8080
  }

  Tapper.server_address(id, endpoint)
  ```
  """

  defstruct [
    :ip,
    :port,
    :service_name,
  ]

  @type ip_address :: :inet.ip_address

  @type t :: %__MODULE__{ip: ip_address, port: integer(), service_name: String.t}

  @doc "get the first non-loopback IP interface address tuple, preferring ipv4 over ip6"
  @spec host_ip() :: Tapper.ip_address
  def host_ip() do
    {:ok, addresses} = :inet.getifaddrs()

    ips = for {_, opts} <- addresses,
        {:addr, addr} <- opts,
        {:flags, flags} <- opts,
        :loopback in flags != true, do: addr

    case ips do # NB when off network, there may not be a non-loopback address!
      [] -> {127, 0, 0, 1}
      ips ->
        # prefer ipv4 (it's shorter than an ipv6, so sorts first)
        hd(:lists.keysort(1, ips))
    end
  end

end
