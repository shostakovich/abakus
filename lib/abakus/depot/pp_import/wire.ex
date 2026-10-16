defmodule Abakus.Depot.PPImport.Wire do
  @moduledoc """
  The protobuf wire format: splits a message into `{field_number, raw_value}` pairs. A varint
  comes back as a non-negative integer, everything else as a binary; what the bytes mean is up
  to the caller.
  """

  import Bitwise

  @uint64 0xFFFF_FFFF_FFFF_FFFF

  @doc "Decodes one message into its fields in file order."
  def decode(bin) when is_binary(bin), do: decode(bin, [])

  defp decode(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode(bin, acc) do
    with {:ok, key, rest} <- varint(bin),
         {:ok, value, rest} <- value(key &&& 7, rest) do
      decode(rest, [{key >>> 3, value} | acc])
    end
  end

  defp value(0, bin), do: varint(bin)
  defp value(1, <<v::binary-size(8), rest::binary>>), do: {:ok, v, rest}
  defp value(5, <<v::binary-size(4), rest::binary>>), do: {:ok, v, rest}

  defp value(2, bin) do
    with {:ok, size, rest} <- varint(bin) do
      case rest do
        <<v::binary-size(^size), rest::binary>> -> {:ok, v, rest}
        _ -> {:error, :malformed}
      end
    end
  end

  defp value(_wire_type, _bin), do: {:error, :malformed}

  @doc "Reads a base-128 varint of at most ten bytes."
  def varint(bin), do: varint(bin, 0, 0)

  defp varint(<<1::1, low::7, rest::binary>>, shift, acc) when shift < 63,
    do: varint(rest, shift + 7, acc ||| low <<< shift)

  defp varint(<<0::1, low::7, rest::binary>>, shift, acc) when shift <= 63,
    do: {:ok, (acc ||| low <<< shift) &&& @uint64, rest}

  defp varint(_bin, _shift, _acc), do: {:error, :malformed}

  @doc "Reinterprets a varint as a signed 64-bit integer (int64 and int32 fields)."
  def signed(v) when v >= 1 <<< 63, do: v - (1 <<< 64)
  def signed(v), do: v
end
