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

  # NB dialyzer hates HTTPPoison.Base
  use HTTPoison.Base

  @behaviour Tapper.Reporter.Api

  @options hackney: [pool: :tapper]

  def ingest(spans) when is_list(spans) do
    Logger.debug(fn -> "Sending #{length(spans)} spans to Zipkin" end)

    url = url()

    # result = HTTPoison.post!(url, data, [{"Content-Type", "application/json"}], @options)
    result = post!(url, spans)

    Logger.debug(fn -> inspect(result) end)

    :ok
  end

  def url() do
    env(config()[:collector_url]) || raise ArgumentError, "#{__MODULE__} reporter needs collector_url configuration"
  end

  @doc "HTTPPoison.Base callback"
  def process_request_body(spans) do
      Tapper.Encoder.Json.encode!(spans)
  end

  @doc "HTTPPoison.Base callback"
  def process_request_headers(headers) do
    [{"Content-Type", "application/json"} | headers]
  end

  @doc "HTTPPoison.Base callback"
  def process_request_options(options) do
    [@options | options]
  end

  def config() do
    Application.get_env(:tapper, __MODULE__)
  end

  defp env({:system, name}), do: System.get_env(name)
  defp env(val), do: val
end
