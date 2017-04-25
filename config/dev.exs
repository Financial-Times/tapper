use Mix.Config

config :tapper,
    system_id: "tapper-dev",
    reporter: Tapper.Reporter.Zipkin,
    collector_url: "http://localhost:9411/api/v1/spans"
