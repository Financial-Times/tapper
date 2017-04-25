defmodule Tapper.Application do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    ipv4 = host_ip()

    config = %{
      host_info: %{
        ipv4: Application.get_env(:tapper, :ipv4, ipv4),
        system_id: Application.get_env(:tapper, :system_id, "unknown")
      },
      reporter: Application.get_env(:tapper, :reporter, Tapper.Reporter.Console)
    }

    Logger.info("Starting Tapper Application")
    # Define workers and child supervisors to be supervised
    children = [
      supervisor(Registry, [:unique, Tapper.Tracers]),
      supervisor(Tapper.TracerSupervisor, [config]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tapper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc "get the first non-loopback IPv4 interface address tuple"
  @spec host_ip() :: {integer(), integer(), integer(), integer()}
  def host_ip() do
    {:ok, addresses} = :inet.getifaddrs()

    ips = for {_, opts} <- addresses, 
        {:addr, addr} <- opts, 
        {:flags, flags} <- opts,
        :loopback in flags != true, 
        tuple_size(addr) == 4, do: addr

    case ips do # NB when off network, won't be a non-loopback address!
      [] -> {127,0,0,1}
      _ -> hd(ips)
    end

  end

end
