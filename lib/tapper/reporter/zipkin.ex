defmodule Tapper.Reporter.Zipkin do
  @moduledoc """
  Reporter that sends spans to Zipkin Server API.

  * Currently supports only JSON encoding.
  * Does not batch spans: would probably be done with an intermediate.

  ## See also

  * `Tapper.Application` - reporter is selection.
  * `Tapper.Reporter.Api` - the implemented behaviour.

  ## Configuration

  | key | purpose |
  | --- | ------- |
  | `collector_url` | Full URL of Zipkin collector endpoint |

  e.g.
  ```
  config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "https://my-zipkin.domain.com:9411/api/v1/spans"
  ```
  """

  require Logger

  import Tapper.Config, only: [env: 1]

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

    case result do
      {:ok, %HTTPoison.Response{status_code: 202}} ->
        Logger.debug(fn -> "Spans sent OK." end)
      {:ok, response = %HTTPoison.Response{status_code: status}} ->
        Logger.warn(fn -> "Failed to send spans: status=#{status} #{inspect response}" end)
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn(fn -> "HTTP Protocol Error sending spans: #{reason}" end)
    end

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

end
