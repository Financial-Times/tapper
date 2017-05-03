defmodule Tapper.Reporter.Zipkin do
  @moduledoc "Reporter that sends spans to Zipkin Server API"

  require Logger

  use HTTPoison.Base

  @behaviour Tapper.Reporter.Api

  @options hackney: [pool: :tapper]

  def ingest(spans) when is_list(spans) do
    Logger.debug(fn -> "Sending #{length(spans)} spans to Zipkin" end)

    url = env(Application.get_env(:tapper, :collector_url))

    # result = HTTPoison.post!(url, data, [{"Content-Type", "application/json"}], @options)
    result = post!(url, spans)

    Logger.debug(fn -> inspect(result) end)

    :ok
  end

  defp env({:system, name}), do: System.get_env(name)
  defp env(val), do: val

  def process_request_body(spans) do
      Tapper.Encoder.Json.encode!(spans)
  end

  def process_request_headers(headers) do
    [{"Content-Type", "application/json"} | headers]
  end

  def process_request_options(options) do
    [@options | options]
  end

end
