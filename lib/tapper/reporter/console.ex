defmodule Tapper.Reporter.Console do
  @moduledoc "Reporter that just logs JSON"

  require Logger

  @behaviour Tapper.Reporter.Api

  def ingest(spans) when is_list(spans) do
    Logger.info(fn -> inspect(IO.iodata_to_binary(Tapper.Encoder.Json.encode!(spans))) end)
  end
end
