use Mix.Config

config :tapper,
    system_id: "tapper-prod",
    reporter: Tapper.Reporter.Zipkin,
    collector_url: {:system, "COLLECTOR_URL"}
