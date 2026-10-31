defmodule Abakus.Sync.ClockTest do
  use ExUnit.Case, async: true

  alias Abakus.Sync.Clock

  @ten ~U[2026-11-02 10:00:00.000Z] |> DateTime.to_unix(:millisecond)

  test "its text is the UTC time with milliseconds, the counter in hex and the device" do
    clock = %Clock{millis: @ten + 5, counter: 26, device: "mac"}

    assert Clock.to_string(clock) == "2026-11-02T10:00:00.005Z-001a-mac"
    assert Clock.parse("2026-11-02T10:00:00.005Z-001a-mac") == {:ok, clock}
  end

  test "parses only text written as it writes it" do
    for text <- [
          "2026-11-02T10:00:00.005Z-001A-mac",
          "2026-11-02T10:00:00.005+00:00-0001-mac",
          "2026-11-02T10:00:00.005Z-0001-",
          "2026-11-02T10:00:00.005Z-0001-Mac",
          "2026-11-02T10:00:00Z-0001-mac",
          nil
        ] do
      assert Clock.parse(text) == :error, inspect(text)
    end
  end

  test "ticks to the wall time, or counts on while that is not later" do
    assert Clock.tick(nil, @ten, "server") == %Clock{millis: @ten, counter: 0, device: "server"}

    last = %Clock{millis: @ten, counter: 3, device: "mac"}

    assert Clock.tick(last, @ten - 1, "server") == %Clock{
             millis: @ten,
             counter: 4,
             device: "server"
           }

    assert Clock.tick(last, @ten, "server") == %Clock{millis: @ten, counter: 4, device: "server"}

    assert Clock.tick(last, @ten + 1, "server") == %Clock{
             millis: @ten + 1,
             counter: 0,
             device: "server"
           }
  end

  test "a full counter moves on to the next millisecond" do
    last = %Clock{millis: @ten, counter: 0xFFFF, device: "mac"}

    assert Clock.tick(last, @ten, "server") == %Clock{
             millis: @ten + 1,
             counter: 0,
             device: "server"
           }
  end

  test "texts sort like their clocks" do
    clocks = [
      %Clock{millis: @ten, counter: 0, device: "server"},
      %Clock{millis: @ten, counter: 1, device: "mac"},
      %Clock{millis: @ten, counter: 1, device: "server"},
      %Clock{millis: @ten + 1, counter: 0, device: "mac"}
    ]

    texts = Enum.map(clocks, &Clock.to_string/1)
    assert Enum.sort(texts) == texts
  end
end
