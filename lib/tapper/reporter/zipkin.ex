defmodule Tapper.Reporter.Zipkin do
  @moduledoc """
  Reporter that sends spans to Zipkin Server API.

  * Currently supports only JSON encoding.
  * Use AsyncReporter with this module as a sender to send spans in batches

  ## See also

  * `Tapper.Application` - reporter selection, also `Tapper.start/1`, `Tapper.join/6` via `reporter` option.
  * `Tapper.Reporter.Api` - the implemented behaviour.

  ## Configuration

  | key | purpose | default/required |
  | --- | ------- | ---------------- |
  | `collector_url` | Full URL of Zipkin collector endpoint<sup>[1]</sup> | Required |
  | `client_opts` | additional options for `HTTPoison` client, see `HTTPoison.Base.request/5` | `ssl: [{:versions, [:'tlsv1.2']}], hackney: [pool: __MODULE__]` |

  e.g.
  ```
  config :tapper, Tapper.Reporter.Zipkin,
    collector_url: "https://my-zipkin.domain.com:9411/api/v1/spans"
    client_opts: [timeout: 10000]
  ```

  <sup>[1]</sup> Tapper uses the [`DeferredConfig`](https://hexdocs.pm/deferred_config/readme.html) library to
  resolve all configuration under the `:tapper` key, so see its documention for options.

  """

  require Logger

  @behaviour Tapper.Reporter.Api

  @options ssl: [{:versions, [:'tlsv1.2']}], hackney: [pool: __MODULE__]

  def ingest(spans) when is_list(spans) do

    # we did use HTTPoison.Base unfortunately, plays badly with Dialyzer & ExDoc
    url = url()
    data = process_request_body(spans)
    headers = process_request_headers([])
    options = process_request_options(@options)

    result = HTTPoison.post(url, data, headers, options)

    case result do
      {:ok, %HTTPoison.Response{status_code: 202}} ->
        :ok
      {:ok, response = %HTTPoison.Response{status_code: status}} ->
        Logger.warn(fn -> "Failed to send spans: status=#{status} #{inspect response}" end)
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn(fn -> "HTTP Protocol Error sending spans: #{reason}" end)
    end

    :ok
  end

  @spec url() :: String.t
  def url() do
    config()[:collector_url] || raise ArgumentError, "#{__MODULE__} reporter needs collector_url configuration"
  end

  def process_request_body(spans) do
      Tapper.Encoder.Json.encode!(spans)
  end

  def process_request_headers(headers) do
    [{"Content-Type", "application/json"} | headers]
  end

  def process_request_options(options) do
    client_opts = config()[:client_opts] || []
    client_opts ++ options
  end

  def config() do
    Application.get_env(:tapper, __MODULE__)
  end

end
