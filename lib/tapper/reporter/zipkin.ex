defmodule Tapper.Reporter.Zipkin do
    require Logger

    def ingest(spans) when is_list(spans) do
        Logger.debug(fn -> "Sending spans to Zipkin" end)

        data = Tapper.Encoder.Json.encode!(spans)
        result = HTTPoison.post!("http://localhost:9411/api/v1/spans", data, [{"Content-Type", "application/json"}])

        Logger.debug(fn -> inspect(result) end)
    end
end
