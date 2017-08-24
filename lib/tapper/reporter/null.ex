defmodule Tapper.Reporter.Null do
  @moduledoc "Reporter that does absolutely nothing with spans"

  @behaviour Tapper.Reporter.Api

  @doc false
  def ingest(spans) when is_list(spans) do
    :ok
  end
end
