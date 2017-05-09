defmodule Tapper.Application do
  @moduledoc """
  Tapper main application; configures and starts application supervisor.

  Add `:tapper` to your application's `mix.exs`:

  ```
  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [mod: {MyApp, []},
     applications: [
       :tapper
       # other applications
      ]]
  end
  ```

  ## Configuration

  Looks for configuration under `:tapper` key.

  | key | purpose |
  | -- | -- |
  | `system_id` | This application's id; used for `service_name` in default [`Endpoint`](Tapper.Endpoint.html) used in annotations. |
  | `ip` | This application's principle IPV4 or IPV6 address, as tuple of ints; defaults to IP of first non-loopback interface, or `{127.0.0.1}` if none. |
  | `reporter` | Module implementing `Tapper.Reporter.Api` to use for reporting spans, defaults to `Tapper.Reporter.Console`. |

  ## Example
  In `config.exs` etc.:

  ```
  config :tapper,
    system_id: "my-cool-svc",
    reporter: Tapper.Reporter.Zipkin
  ```
  """

  use Application
  require Logger

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    config = %{
      host_info: %{
        ip: Application.get_env(:tapper, :ip, Tapper.Endpoint.host_ip()),
        system_id: Application.get_env(:tapper, :system_id, "unknown")
      },
      reporter: Application.get_env(:tapper, :reporter, Tapper.Reporter.Console)
    }

    Logger.info("Starting Tapper Application")
    # Define workers and child supervisors to be supervised
    children = [
      supervisor(Registry, [:unique, Tapper.Tracers]),
      supervisor(Tapper.Tracer.Supervisor, [config]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tapper.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
