defmodule Tapper.Endpoint do
  @moduledoc """
  Endpoint description struct; used everywhere an endpoint is required.

  ## Example
  ```
  endpoint = %Endpoint{
    ip: {192, 168, 10, 100},
    service_name: "my-service",
    port: 80
  }

  Tapper.server_address(id, endpoint)
  ```

  The `ip` field is either an IPV4 or an IPV6 address, as a 4- or 8-tuple; the
  port will default to `0`.

  Instead of an `ip` address, the `hostname` field can provide a DNS name
  (as a `String.t` or `atom`) which will be resolved to an IP address
  (see `Tapper.Tracer.Trace.Convert`) when the span is reported:

  ```
  endpoint = %Endpoint{
    hostname: "my-service.ft.com",
    service_name: "my-service",
    port: 80
  }
  ```

  > NB because DNS resolution happens asynchronously, the resulting IP address may
  not correspond the actual IP address connected to, e.g. if the service
  is being IP load-balanced (e.g. by A record or AWS ALB). You can use the
  `resolve/1` function before sending an annotation to make it *slightly more likely*
  to be the same IP address, at the expense of doing this in the client process,
  rather than in Tapper's server.
  """

  defstruct [
    :ip,
    :port,
    :service_name,
    :hostname
  ]

  @type ip_address :: :inet.ip_address

  @type t :: %__MODULE__{
    ip: ip_address | nil,
    port: integer() | nil,
    service_name: String.t | nil,
    hostname: String.t | atom() | nil
  }

  @spec resolve(endpoint :: __MODULE__.t) :: __MODULE__.t
  def resolve(endpoint)

  def resolve(endpoint = %__MODULE__{hostname: hostname}) when not is_nil(hostname) do
    hostent = gethostbyname(hostname)
    apply_hostent(endpoint, hostent)
  end

  def resolve(endpoint = %__MODULE__{}), do: endpoint

  def apply_hostent(endpoint, {:ok, {:hostent, _, _, :inet, _, [ipv4 | _]}}) do
    %{endpoint | ip: ipv4}
  end
  def apply_hostent(endpoint, {:ok, {:hostent, _, _, :inet6, _, [ipv6 | _]}}) do
    %{endpoint | ip: ipv6}
  end
  def apply_hostent(endpoint, _) do
    endpoint
  end

  defp gethostbyname(hostname) when is_binary(hostname) do
    gethostbyname(String.to_charlist(hostname))
  end
  if Mix.env == :test do
    defp gethostbyname(:inet6) do
      {:ok, {:hostent, :inet6, [], :inet6, 16, [{1111, 1, 1, 1, 1, 1, 1, 1111}]}}
    end
    defp gethostbyname(hostname) do
      {:ok, {:hostent, hostname, [], :inet, 4, [{10, 1, 1, 10}]}}
    end
  else
    defp gethostbyname(hostname) do
      :inet.gethostbyname(hostname) # NB accepts an atom or charlist
    end
  end

  @doc "get the first non-loopback IP interface address tuple, preferring ipv4 over ip6"
  @spec host_ip() :: Tapper.ip_address
  def host_ip do
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
