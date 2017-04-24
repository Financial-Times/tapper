use Mix.Config

config :tapper,
    system_id: "tapper-dev",
    reporter: Tapper.Reporter.Zipkin
