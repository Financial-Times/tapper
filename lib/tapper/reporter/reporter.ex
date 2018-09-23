defmodule Tapper.Reporter do
  @moduledoc "Generic reporter support functions."

  @doc """
  Raises if the given `reporter` is not a module implementing the `Tapper.Reporer.Api`
  behaviour, nor a function with artity 1; else returns `reporter`.
  """
  def ensure_reporter!(reporter) do
    cond do
      is_atom(reporter) and Tapper.Config.behaves_as?(reporter, Tapper.Reporter.Api) ->
        reporter

      is_function(reporter, 1) ->
        reporter

      true ->
        raise "Expected #{Macro.to_string(reporter)} to be a module with Tapper.Reporter.Api behaviour, or a function with arity 1"
    end
  end

  @doc "sends spans to a reporter; supports function and module reporters"
  def send(reporter, spans) do
    case reporter do
      fun when is_function(fun, 1) -> fun.(spans)
      mod when is_atom(mod) -> apply(mod, :ingest, [spans])
    end
  end
end
