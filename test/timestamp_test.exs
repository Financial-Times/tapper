defmodule TimestampTest do
  @moduledoc false

  use ExUnit.Case

  alias Tapper.Timestamp

  test "timestamp/1 is {monotonic_time, time_offset} in native units" do
    {{timestamp, offset}, {system_time, system_offset}} = {Timestamp.instant(), {System.monotonic_time, System.time_offset}}
    assert_in_delta timestamp, system_time, 1_000_000
    assert_in_delta offset, system_offset, 1_000_000
  end

  test "to_absolute/1 adjusts instant to offset and microseconds" do
    ts = {timestamp, offset} = Timestamp.instant()

    assert Timestamp.to_absolute(ts) == System.convert_time_unit(timestamp + offset, :native, :microsecond)
  end

  test "duration/2 calculates difference in microseconds" do
    t1 = {timestamp, _offset} = Timestamp.instant()
    t2 = {timestamp + 5_000, 100_000_000}

    assert Timestamp.duration(t1, t2) === System.convert_time_unit(5_000, :native, :microsecond)
  end

  test "incr/3 adds in native units" do
    t = {timestamp, offset} = Timestamp.instant()
    assert Timestamp.incr(t, 50, :millisecond) == {
      timestamp + System.convert_time_unit(50, :millisecond, :native), offset
    }
  end

end
