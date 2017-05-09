defmodule Tapper.Reporter.Zipkin do
  @moduledoc """
  Reporter that sends spans to Zipkin Server API.

  Currently supports only JSON encoding.

  ## See also

  * `Tapper.Application`

  ## Configuration

  | key | purpose |
  | --- | ------- |
  | `collector_url` | Full URL of Zipkin collector endpoint |

  ```
  config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "https://my-zipkin.domain.com:9411/api/v1/spans"
  ```
  """

  require Logger

  @behaviour Tapper.Reporter.Api

  @options hackney: [ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 5000, hackney: [pool: :tapper]]

  def ingest(spans) when is_list(spans) do
    Logger.debug(fn -> "Sending #{length(spans)} spans to Zipkin" end)

    # we did use HTTPoison.Base unfortunately, plays badly with Dialyzer & ExDoc
    url = url()
    data = process_request_body(spans)
    headers = process_request_headers([])
    options = process_request_options([])

    result = HTTPoison.post(url, data, headers, options)

    Logger.debug(fn -> inspect(result) end)

    :ok
  end

  def url() do
    env(config()[:collector_url]) || raise ArgumentError, "#{__MODULE__} reporter needs collector_url configuration"
  end

  def process_request_body(spans) do
      Tapper.Encoder.Json.encode!(spans)
  end

  def process_request_headers(headers) do
    [{"Content-Type", "application/json"} | headers]
  end

  def process_request_options(options) do
    [@options | options]
  end

  def config() do
    Application.get_env(:tapper, __MODULE__)
  end

  defp env({:system, name}), do: System.get_env(name)
  defp env(val), do: val
end
