defmodule Tapper.Reporter.Api do
  @moduledoc "Reporter modules should implement this behaviour."

  @doc "Ingest a list of [`%Tapper.Protocol.Span{}`](Tapper.Protocol.Span.html)"
  @callback ingest(spans :: [Tapper.Protocol.Span.t]) :: :ok
end
