defmodule Tapper.Timestamp do
  @moduledoc "Timestamp"

  @type microseconds_timestamp :: integer()
  @type native_timestamp :: integer()
  @type offset :: integer()

  @type t :: {native_timestamp(), offset()}

  @spec instant() :: t
  def instant do
    {System.monotonic_time(), System.time_offset()}
  end

  @spec to_absolute(t) :: microseconds_timestamp()
  def to_absolute({timestamp, offset}) do
    System.convert_time_unit(timestamp + offset, :native, :microseconds)
  end

  @spec duration(t1 :: t, t2 :: t) :: microseconds_timestamp()
  def duration({timestamp1, _}, {timestamp2, _}) do
    System.convert_time_unit(timestamp2 - timestamp1, :native, :microseconds)
  end

  @spec incr(t, increment :: integer(), units :: System.time_unit | :native) :: t
  def incr(timestamp, increment, units \\ :native)

  def incr({timestamp, offset}, increment, units) do
    {timestamp + System.convert_time_unit(increment, units, :native), offset}
  end

end
