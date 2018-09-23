use Mix.Config

config :tapper,
    system_id: "tapper-dev",
    reporter: {Tapper.Reporter.AsyncReporter, []},
    server_trace: :info

config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "http://localhost:9411/api/v1/spans"

config :tapper, Tapper.Reporter.AsyncReporter,
  flush_interval: 10000,
  max_spans_threshold: 1000,
  max_concurrent_flush_count: 5,
  sender: Tapper.Reporter.Zipkin
