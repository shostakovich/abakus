defmodule Abakus.Sync.Clock do
  @moduledoc """
  A hybrid logical clock (`sync/PROTOCOL.md`): wall time in milliseconds, a counter and the device, compared in that
  order. Its text, `2026-11-02T10:00:00.000Z-0000-server`, sorts like the clock: UTC time with milliseconds, the
  counter as four hex digits, the device id. A counter past `ffff` moves the clock on to the next millisecond.
  """

  @enforce_keys [:millis, :counter, :device]
  defstruct [:millis, :counter, :device]

  @max_counter 0xFFFF

  @doc "The clock a writer stamps its next change with, after its newest clock `last` (nil for none)."
  def tick(nil, now_millis, device),
    do: %__MODULE__{millis: now_millis, counter: 0, device: device}

  def tick(%__MODULE__{millis: millis, counter: counter}, now_millis, device) do
    cond do
      now_millis > millis -> %__MODULE__{millis: now_millis, counter: 0, device: device}
      counter == @max_counter -> %__MODULE__{millis: millis + 1, counter: 0, device: device}
      true -> %__MODULE__{millis: millis, counter: counter + 1, device: device}
    end
  end

  @doc "Parses a clock's text, which must be written as `to_string/1` writes it; `:error` when it is none."
  def parse(<<time::binary-size(24), "-", counter::binary-size(4), "-", device::binary>> = text) do
    with {:ok, moment, 0} <- DateTime.from_iso8601(time),
         {counter, ""} <- Integer.parse(counter, 16),
         true <- String.match?(device, ~r/\A[a-z0-9-]+\z/),
         clock = %__MODULE__{
           millis: DateTime.to_unix(moment, :millisecond),
           counter: counter,
           device: device
         },
         ^text <- __MODULE__.to_string(clock) do
      {:ok, clock}
    else
      _invalid -> :error
    end
  end

  def parse(_text), do: :error

  @doc "The clock's text."
  def to_string(%__MODULE__{millis: millis, counter: counter, device: device}) do
    time = millis |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
    hex = counter |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
    "#{time}-#{hex}-#{device}"
  end
end
