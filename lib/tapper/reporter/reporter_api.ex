defmodule Tapper.Reporter.Api do
  @moduledoc "Reporter modules should implement this behaviour"

  @callback ingest(spans :: [Tapper.Protocol.Span.t]) :: :ok
end
