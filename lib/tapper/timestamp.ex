defmodule Tapper.Timestamp do
  @moduledoc "Timestamp support functions."

  @type microseconds_timestamp :: integer()
  @type native_timestamp :: integer()
  @type offset :: integer()

  @type t :: {native_timestamp(), offset()}

  @doc "Produce a high-resolution timestamp for this very instant, compatible with the Tapper API."
  @spec instant() :: t
  def instant do
    {System.monotonic_time(), System.time_offset()}
  end

  @doc "Convert the timestamp to an absolute time, in microseconds since the epoch."
  @spec to_absolute(t :: t) :: microseconds_timestamp()
  def to_absolute(timestamp)
  def to_absolute({timestamp, offset}) do
    System.convert_time_unit(timestamp + offset, :native, :microseconds)
  end

  @doc "Calculate the different between two timestamp, in microseconds."
  @spec duration(t1 :: t, t2 :: t) :: microseconds_timestamp()
  def duration(t1, t2)
  def duration({timestamp1, _}, {timestamp2, _}) do
    System.convert_time_unit(timestamp2 - timestamp1, :native, :microseconds)
  end

  @doc false
  @spec incr(t, increment :: integer(), units :: System.time_unit | :native) :: t
  def incr(timestamp, increment, units \\ :native)

  def incr({timestamp, offset}, increment, units) do
    {timestamp + System.convert_time_unit(increment, units, :native), offset}
  end

end
