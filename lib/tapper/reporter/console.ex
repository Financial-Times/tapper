defmodule Tapper.Reporter.Console do
    require Logger

    def ingest(spans) when is_list(spans) do
        spans
        |> Enum.each(fn(span) ->
            Logger.debug(fn -> inspect({:span, span}) end)
        end)
    end
end