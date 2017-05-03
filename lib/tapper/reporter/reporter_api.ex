defmodule Tapper.Reporter.Api do
  @callback ingest(spans :: [Tapper.Protocol.Span.t]) :: :ok
end
