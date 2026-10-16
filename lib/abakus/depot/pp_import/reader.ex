defmodule Abakus.Depot.PPImport.Reader do
  @moduledoc """
  Reads a PP file: a ZIP with `data.portfolio`, which is `PPPBV1` followed by a protobuf
  `PClient`. Field numbers follow PP's `client.proto`; only the fields the Depot keeps are
  listed, all others are skipped. Messages become maps with atom keys.
  """

  alias Abakus.Depot.PPImport.Wire

  # {name, type} or {name, type, :repeated | :optional}. Absent optional fields are nil,
  # absent scalars take the proto3 default ("", 0, false, first enum value).
  @messages %{
    client: %{
      1 => {:version, :int32},
      2 => {:securities, {:message, :security}, :repeated},
      3 => {:accounts, {:message, :account}, :repeated},
      4 => {:portfolios, {:message, :portfolio}, :repeated},
      5 => {:transactions, {:message, :transaction}, :repeated},
      6 => {:plans, {:message, :plan}, :repeated},
      8 => {:taxonomies, {:message, :taxonomy}, :repeated},
      11 => {:settings, {:message, :settings}, :optional},
      12 => {:base_currency, :string}
    },
    security: %{
      1 => {:uuid, :string},
      3 => {:name, :string},
      4 => {:currency, :string, :optional},
      6 => {:note, :string, :optional},
      7 => {:isin, :string, :optional},
      8 => {:ticker, :string, :optional},
      9 => {:wkn, :string, :optional},
      11 => {:feed, :string, :optional},
      13 => {:prices, {:message, :price}, :repeated},
      16 => {:latest, {:message, :price}, :optional},
      17 => {:attributes, :attributes},
      20 => {:retired, :bool}
    },
    price: %{1 => {:date, :epoch_day}, 2 => {:close, :int64}},
    account: %{
      1 => {:uuid, :string},
      2 => {:name, :string},
      3 => {:currency, :string},
      4 => {:note, :string, :optional},
      5 => {:retired, :bool},
      6 => {:attributes, :attributes}
    },
    portfolio: %{
      1 => {:uuid, :string},
      2 => {:name, :string},
      3 => {:note, :string, :optional},
      4 => {:retired, :bool},
      5 => {:reference_account, :string, :optional},
      6 => {:attributes, :attributes}
    },
    transaction: %{
      1 => {:uuid, :string},
      2 =>
        {:type,
         {:enum,
          ~w(buy sell inbound_delivery outbound_delivery security_transfer cash_transfer deposit
             removal dividend interest interest_charge tax tax_refund fee fee_refund)a}},
      3 => {:account, :string, :optional},
      4 => {:portfolio, :string, :optional},
      5 => {:other_account, :string, :optional},
      6 => {:other_portfolio, :string, :optional},
      7 => {:other_uuid, :string, :optional},
      9 => {:date_time, :timestamp},
      10 => {:currency, :string},
      11 => {:amount, :int64},
      12 => {:shares, :int64, :optional},
      13 => {:note, :string, :optional},
      14 => {:security, :string, :optional},
      15 => {:units, {:message, :unit}, :repeated},
      17 => {:source, :string, :optional},
      18 => {:ex_date, :local_date_time, :optional}
    },
    unit: %{
      1 => {:type, {:enum, [:gross_value, :tax, :fee]}},
      2 => {:amount, :int64},
      3 => {:currency, :string},
      4 => {:fx_amount, :int64, :optional},
      5 => {:fx_currency, :string, :optional},
      6 => {:fx_rate, :decimal, :optional}
    },
    plan: %{
      1 => {:name, :string},
      2 => {:note, :string, :optional},
      3 => {:security, :string, :optional},
      4 => {:portfolio, :string, :optional},
      5 => {:account, :string, :optional},
      6 => {:attributes, :attributes},
      7 => {:auto_generate, :bool},
      8 => {:start, :epoch_day},
      9 => {:interval, :int32},
      10 => {:amount, :int64},
      11 => {:fees, :int64},
      12 => {:transactions, :string, :repeated},
      13 => {:taxes, :int64},
      14 => {:type, {:enum, [:purchase_or_delivery, :deposit, :removal, :interest]}}
    },
    taxonomy: %{
      1 => {:id, :string},
      2 => {:name, :string},
      3 => {:source, :string, :optional},
      4 => {:dimensions, :string, :repeated},
      5 => {:classifications, {:message, :classification}, :repeated}
    },
    classification: %{
      1 => {:id, :string},
      2 => {:parent_id, :string, :optional},
      3 => {:name, :string},
      4 => {:note, :string, :optional},
      5 => {:color, :string, :optional},
      6 => {:weight, :int32},
      7 => {:rank, :int32},
      9 => {:assignments, {:message, :assignment}, :repeated}
    },
    assignment: %{
      1 => {:vehicle, :string},
      2 => {:weight, :int32},
      3 => {:rank, :int32}
    },
    settings: %{2 => {:attribute_types, {:message, :attribute_type}, :repeated}},
    attribute_type: %{
      1 => {:id, :string},
      2 => {:name, :string},
      3 => {:column_label, :string, :optional},
      5 => {:target, :string, :optional},
      6 => {:value_type, :string, :optional},
      7 => {:converter, :string, :optional}
    },
    key_value: %{1 => {:key, :string}, 2 => {:value, :any, :optional}},
    any: %{
      2 => {:string, :string, :optional},
      3 => {:int32, :int32, :optional},
      4 => {:int64, :int64, :optional},
      5 => {:double, :double, :optional},
      6 => {:bool, :bool, :optional},
      7 => {:map, {:message, :map}, :optional}
    },
    map: %{1 => {:entries, :attributes}},
    timestamp: %{1 => {:seconds, :int64}, 2 => {:nanos, :int32}},
    local_date_time: %{1 => {:epoch_day, :int64}, 2 => {:second_of_day, :int32}},
    decimal: %{1 => {:scale, :uint32}, 3 => {:value, :bytes}}
  }

  @epoch ~D[1970-01-01]

  # Per message: the map an empty message decodes to, and the fields collected in reverse.
  @defaults Map.new(@messages, fn {message, spec} ->
              defaults =
                Map.new(spec, fn {_number, field} ->
                  default =
                    case field do
                      {_, _, :repeated} -> []
                      {_, _, :optional} -> nil
                      {_, :attributes} -> %{}
                      {_, :bool} -> false
                      {_, :string} -> ""
                      {_, {:enum, [first | _]}} -> first
                      {_, type} when type in [:int32, :int64, :uint32] -> 0
                      {_, :epoch_day} -> @epoch
                      _ -> nil
                    end

                  {elem(field, 0), default}
                end)

              {message, defaults}
            end)

  @repeated Map.new(@messages, fn {message, spec} ->
              {message, for({_, {name, _, :repeated}} <- spec, do: name)}
            end)

  @max_unpacked 500_000_000

  @doc "Reads a PP file from disk."
  def read(path) do
    case File.read(path) do
      {:ok, bin} -> parse(bin)
      {:error, _} -> {:error, :not_a_pp_file}
    end
  end

  @doc """
  Parses the contents of a PP file. An entry unpacking to more than `max_unpacked` bytes (default 500 MB) is
  `{:error, :too_large}`.
  """
  def parse(bin, opts \\ []) do
    with {:ok, files} <- unzip(bin, Keyword.get(opts, :max_unpacked, @max_unpacked)) do
      case {List.keyfind(files, ~c"data.portfolio", 0), List.keymember?(files, ~c"data.xml", 0)} do
        {{_, <<"PPPBV1", data::binary>>}, _} -> message(data, :client)
        {nil, true} -> {:error, :xml_format}
        _ -> {:error, :not_a_pp_file}
      end
    end
  end

  # Only PP's own entries are unpacked, and only up to a sane size counted while inflating, as a
  # crafted ZIP can declare any size.
  @entries [~c"data.portfolio", ~c"data.xml"]

  defp unzip(bin, max) do
    with {:ok, [_comment | listing]} <- :zip.list_dir(bin) do
      listing
      |> Enum.filter(&match?({:zip_file, name, _, _, _, _} when name in @entries, &1))
      |> Enum.reduce_while({:ok, []}, &unzip_entry(bin, &1, &2, max))
    end
    |> case do
      {:ok, files} -> {:ok, files}
      {:error, :too_large} -> {:error, :too_large}
      _error -> {:error, :not_a_pp_file}
    end
  end

  defp unzip_entry(bin, {:zip_file, name, info, _, offset, size}, {:ok, files}, max) do
    with :ok <- check_size(elem(info, 1), max),
         {:ok, content} <- unpack(bin, offset, size, max) do
      {:cont, {:ok, [{name, content} | files]}}
    else
      error -> {:halt, error}
    end
  end

  defp check_size(size, max) when size > max, do: {:error, :too_large}
  defp check_size(_size, _max), do: :ok

  # The local header gives the method and where the data starts; the central directory its size.
  defp unpack(bin, offset, size, max) do
    with <<_::binary-size(^offset), 0x04034B50::little-32, _version::16, flags::little-16,
           method::little-16, _time_date_crc_sizes::binary-size(16), name_length::little-16,
           extra_length::little-16, _::binary>> <- bin,
         0 <- Bitwise.band(flags, 1),
         start = offset + 30 + name_length + extra_length,
         <<_::binary-size(^start), data::binary-size(^size), _::binary>> <- bin do
      unpack(method, data, max)
    else
      _ -> {:error, :damaged}
    end
  end

  defp unpack(0, data, max), do: with(:ok <- check_size(byte_size(data), max), do: {:ok, data})
  defp unpack(8, data, max), do: inflate(data, max)
  defp unpack(_method, _data, _max), do: {:error, :unsupported}

  defp inflate(data, max) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate(z, :zlib.safeInflate(z, data), max, [], 0)
    rescue
      ErlangError -> {:error, :damaged}
    after
      :zlib.close(z)
    end
  end

  defp inflate(z, {state, output}, max, acc, size) when state in [:continue, :finished] do
    length = IO.iodata_length(output)

    cond do
      size + length > max -> {:error, :too_large}
      state == :finished -> {:ok, IO.iodata_to_binary(Enum.reverse([output | acc]))}
      # Out of input before the end of the stream.
      length == 0 -> {:error, :damaged}
      true -> inflate(z, :zlib.safeInflate(z, []), max, [output | acc], size + length)
    end
  end

  defp inflate(_z, _result, _max, _acc, _size), do: {:error, :damaged}

  defp message(bin, name) do
    with {:ok, fields} <- Wire.decode(bin),
         {:ok, map} <- collect(fields, @messages[name], @defaults[name]) do
      {:ok,
       Enum.reduce(@repeated[name], map, &Map.update!(&2, &1, fn list -> Enum.reverse(list) end))}
    end
  end

  defp collect([], _spec, acc), do: {:ok, acc}

  defp collect([{number, raw} | rest], spec, acc) do
    case Map.get(spec, number) do
      nil ->
        collect(rest, spec, acc)

      field ->
        with {:ok, acc} <- put(field, raw, acc), do: collect(rest, spec, acc)
    end
  end

  defp put({name, :attributes}, raw, acc) do
    with {:ok, %{key: key, value: value}} <- message(raw, :key_value) do
      {:ok, Map.update!(acc, name, &Map.put(&1, key, value))}
    end
  end

  defp put({name, type, :repeated}, raw, acc) do
    with {:ok, value} <- convert(type, raw), do: {:ok, Map.update!(acc, name, &[value | &1])}
  end

  defp put({name, type, :optional}, raw, acc), do: put({name, type}, raw, acc)

  defp put({name, type}, raw, acc) do
    with {:ok, value} <- convert(type, raw), do: {:ok, Map.put(acc, name, value)}
  end

  defp convert(:string, raw) when is_binary(raw), do: {:ok, raw}
  defp convert(:bytes, raw) when is_binary(raw), do: {:ok, raw}
  defp convert(:bool, raw) when is_integer(raw), do: {:ok, raw != 0}
  defp convert(:uint32, raw) when is_integer(raw), do: {:ok, raw}

  defp convert(type, raw) when type in [:int32, :int64] and is_integer(raw),
    do: {:ok, Wire.signed(raw)}

  defp convert(:epoch_day, raw) when is_integer(raw),
    do: {:ok, Date.add(@epoch, Wire.signed(raw))}

  defp convert(:double, <<v::float-little-64>>), do: {:ok, v}

  defp convert({:enum, values}, raw) when is_integer(raw) do
    case Enum.at(values, raw) do
      nil -> {:error, :malformed}
      value -> {:ok, value}
    end
  end

  defp convert({:message, name}, raw) when is_binary(raw), do: message(raw, name)

  defp convert(:timestamp, raw) when is_binary(raw) do
    # PP writes local date-times as if they were UTC.
    with {:ok, %{seconds: seconds}} <- message(raw, :timestamp) do
      {:ok, NaiveDateTime.add(~N[1970-01-01 00:00:00], seconds)}
    end
  end

  defp convert(:local_date_time, raw) when is_binary(raw) do
    with {:ok, %{epoch_day: day, second_of_day: second}} <- message(raw, :local_date_time) do
      {:ok, NaiveDateTime.add(~N[1970-01-01 00:00:00], day * 86_400 + second)}
    end
  end

  defp convert(:decimal, raw) when is_binary(raw) do
    # An unscaled two's complement big-endian integer, as Java's BigInteger.toByteArray/0.
    with {:ok, %{scale: scale, value: bytes}} <- message(raw, :decimal) do
      size = bit_size(bytes || <<>>)
      <<unscaled::signed-big-size(^size)>> = bytes || <<>>
      {:ok, Decimal.new(if(unscaled < 0, do: -1, else: 1), abs(unscaled), -scale)}
    end
  end

  defp convert(:any, raw) when is_binary(raw) do
    with {:ok, any} <- message(raw, :any) do
      case any do
        %{map: %{entries: entries}} -> {:ok, entries}
        _ -> {:ok, Enum.find(Map.values(any), &(not is_nil(&1)))}
      end
    end
  end

  defp convert(_type, _raw), do: {:error, :malformed}
end
