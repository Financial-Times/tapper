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

  Looks for configuration under `:tapper` key:

  | key         | type     | purpose |
  | --          | --       | --      |
  | `system_id` | String.t | This application's id; used for `service_name` in default [`Endpoint`](Tapper.Endpoint.html) used in annotations; default `unknown` |
  | `ip`        | tuple    | This application's principle IPV4 or IPV6 address, as 4- or 8-tuple of ints; defaults to IP of first non-loopback interface, or `{127.0.0.1}` if none. |
  | `port`      | integer  | The application's principle port, e.g. HTTP port 80; defaults to 0 |
  | `reporter`  | atom     | Module implementing `Tapper.Reporter.Api` to use for reporting spans, defaults to `Tapper.Reporter.Console`. |

  All keys support the Phoenix-style `{:system, var}` format, to allow lookup from shell environment variables, e.g. `{:system, "PORT"}` to read `PORT` environment variable.

  Config values will be converted to the expected type, principally so that string values can be handled from environment variables:
  *  `ip` is expected in dotted IPV4 or colon IPV6 notation, see Erlang's [`inet:parse_address/1`](http://erlang.org/doc/man/inet.html#parse_address-1)
  * `reporter` can be specified as a string which will be converted to an atom, following Elixir's module name rules.

  ## Example
  In `config.exs` etc.:

  ```
  config :tapper,
    system_id: "my-cool-svc",
    reporter: Tapper.Reporter.Zipkin,
    port: {:system, "PORT"}
  ```
  """

  use Application

  require Logger

  import Tapper.Config

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    config = %{
      host_info: %{
        ip: to_ip(env(Application.get_env(:tapper, :ip, Tapper.Endpoint.host_ip()))),
        port: to_int(env(Application.get_env(:tapper, :port, 0))),
        system_id: env(Application.get_env(:tapper, :system_id, "unknown"))
      },
      reporter: env(Application.get_env(:tapper, :reporter, Tapper.Reporter.Console))
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
