defmodule Tapper.Reporter.Zipkin do
  require Logger

  @behaviour Tapper.Reporter.Api

  @options hackney: [pool: :tapper]

  def ingest(spans) when is_list(spans) do
    Logger.debug(fn -> "Sending #{length(spans)} spans to Zipkin" end)

    data = Tapper.Encoder.Json.encode!(spans)

    url = env(Application.get_env(:tapper, :collector_url))
    result = HTTPoison.post!(url, data, [{"Content-Type", "application/json"}], @options)

    Logger.debug(fn -> inspect(result) end)
  end

  defp env({:system, name}), do: System.get_env(name)
  defp env(val), do: val
end
