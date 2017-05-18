defmodule Tapper.Config do
  @moduledoc """
  Support functions for configuration parsing.

  For Tapper configuration, see `Tapper.Application`, for Zipkin configuration, see
  `Tapper.Reporter.Zipkin`.
  """

  def env({:system, var}), do: System.get_env(var)
  def env(val), do: val

  def to_int(val) when is_integer(val), do: val
  def to_int(val) when is_binary(val), do: String.to_integer(val)

  def to_ip(val) when is_tuple(val) and tuple_size(val) === 4, do: val
  def to_ip(val) when is_tuple(val) and tuple_size(val) === 8, do: val
  def to_ip(val) when is_binary(val) do
    {:ok, ip} = :inet_parse.address(String.to_charlist(val))
    ip
  end

  def to_atom(val) when is_atom(val), do: val
  def to_atom(val = "Elixir." <> _rest) when is_binary(val), do: String.to_atom(val)
  def to_atom(val) when is_binary(val), do: String.to_atom("Elixir." <> val)

end
