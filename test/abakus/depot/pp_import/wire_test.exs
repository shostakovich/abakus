defmodule Abakus.Depot.PPImport.WireTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.PPImport.Wire

  test "splits a message into fields of every wire type" do
    # field 1 varint 300, field 2 bytes "hi", field 3 fixed64, field 4 fixed32
    bin = <<0x08, 0xAC, 0x02, 0x12, 2, "hi", 0x19, 1::little-64, 0x25, 2::little-32>>

    assert Wire.decode(bin) ==
             {:ok, [{1, 300}, {2, "hi"}, {3, <<1::little-64>>}, {4, <<2::little-32>>}]}
  end

  test "reads negative int64 from a ten-byte varint" do
    {:ok, [{1, raw}]} =
      Wire.decode(<<0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01>>)

    assert Wire.signed(raw) == -1
  end

  test "rejects truncated data and unknown wire types" do
    assert Wire.decode(<<0x12, 5, "hi">>) == {:error, :malformed}
    assert Wire.decode(<<0x08, 0xAC>>) == {:error, :malformed}
    assert Wire.decode(<<0x0B>>) == {:error, :malformed}

    assert Wire.decode(<<0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01>>) ==
             {:error, :malformed}
  end
end
