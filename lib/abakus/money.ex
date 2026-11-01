defmodule Abakus.Money do
  @moduledoc """
  Amounts as integers in the smallest unit of their currency (euro cents for euros), read from
  German or English input and written the German way, the same in every area: `"1.234,56 €"`.

  Input takes a comma or a dot as decimal separator and the other one as thousands separator.
  A single dot before exactly three digits groups thousands (`"1.234"` is 1234), unless the
  currency has three decimals or only zeros precede it (`"0.856"`). A separator at the end
  (`"12,"`) means whole units; `-` and `−` are minus, spaces and a trailing `€` are ignored.

  A field holds an amount as `amount/2` writes it, without unit, and reads it back unchanged.
  Shown amounts (`euros/2`, `money/2`) go through `Setzkasten.Format.money/2`: a no-break space
  before the unit and a real minus. Stored text (`plain/2`) keeps a plain space.
  """

  @max_cents 1_000_000_000_000
  @blank "Bitte einen Betrag eingeben."
  @not_text "Ungültiger Betrag."
  @zero_decimals ~w(JPY KRW ISK HUF CLP VND XAF XOF PYG UGX IDR)
  @three_decimals ~w(KWD BHD OMR JOD TND LYD IQD)
  @int64_bound :math.pow(2, 63)

  @doc "The largest amount in cents, 10 billion euros, so that splitting cannot overflow."
  def max_cents, do: @max_cents

  @doc "Reads an amount with `decimals` decimal places into minor units; empty or no text is an error."
  @spec parse(term(), 0..3) :: {:ok, integer()} | {:error, String.t()}
  def parse(text, decimals) when is_binary(text) do
    case amount_text(text) do
      "" -> {:error, @blank}
      text -> parse_fixed(text, decimals)
    end
  end

  def parse(_not_text, _decimals), do: {:error, @not_text}

  @doc """
  Reads a number with any number of decimal places, as the Depot takes shares and prices: a
  dot before exactly three digits groups thousands (`"1.500"` is 1500, `"0.125"` stays).
  """
  @spec parse_number(term()) :: {:ok, Decimal.t()} | {:error, String.t()}
  def parse_number(text) when is_binary(text) do
    case amount_text(text) do
      "" -> {:error, @blank}
      text -> parse_decimal_places(text)
    end
  end

  def parse_number(_not_text), do: {:error, @not_text}

  @doc ~s(Reads a percentage into basis points: `"12,5 %"` is 1250.)
  @spec parse_basis_points(String.t()) :: {:ok, integer()} | {:error, String.t()}
  def parse_basis_points(text) do
    text = text |> String.trim() |> String.replace_suffix("%", "") |> String.trim()

    with {:error, _} <- parse_fixed(strip_spaces(text), 2),
         do: {:error, "Ungültige Prozentangabe „#{text}“."}
  end

  @doc "Reads an exchange rate: units of the currency per 1 €. A dot before three digits groups."
  @spec parse_rate(String.t()) :: {:ok, float()} | {:error, String.t()}
  def parse_rate(text) do
    text = text |> String.trim() |> strip_spaces()

    with {:ok, {false, int, frac}} when byte_size(int) <= 12 and byte_size(frac) <= 12 <-
           split_number(text, true),
         {rate, ""} when rate > 0 <- Float.parse(int <> "." <> frac <> "0") do
      {:ok, rate}
    else
      _invalid ->
        {:error,
         "Ungültiger Wechselkurs „#{text}“ – bitte eine Zahl größer als 0 angeben " <>
           "(Einheiten der Währung pro 1 €)."}
    end
  end

  @doc """
  Reads digits with at most `decimals` places after a dot and no thousands separator, as tools
  pass them: `"1.234"` is never 1234.
  """
  @spec parse_decimal(String.t(), 0..3) :: {:ok, non_neg_integer()} | :error
  def parse_decimal(text, decimals) do
    {whole, fraction} =
      case String.split(String.trim(text), ".", parts: 2) do
        [whole, fraction] -> {whole, String.trim_trailing(fraction, "0")}
        [whole] -> {whole, ""}
      end

    if whole =~ ~r/\A[0-9]{1,15}\z/ and fraction =~ ~r/\A[0-9]*\z/ and
         byte_size(fraction) <= decimals,
       do: {:ok, String.to_integer(whole <> String.pad_trailing(fraction, decimals, "0"))},
       else: :error
  end

  defp amount_text(text),
    do: text |> String.trim() |> String.replace_suffix("€", "") |> strip_spaces()

  defp parse_fixed(text, decimals) do
    with {:ok, {negative?, int, frac}} <- split_number(text, decimals < 3),
         frac = trim_zeros(frac, decimals),
         :ok <- check_places(frac, decimals),
         :ok <- check_size(int) do
      value = String.to_integer(int <> String.pad_trailing(frac, decimals, "0"))
      {:ok, if(negative?, do: -value, else: value)}
    else
      :error -> {:error, invalid(text)}
      {:error, _message} = error -> error
    end
  end

  defp parse_decimal_places(text) do
    with {:ok, {negative?, int, frac}} <- split_number(text, true),
         :ok <- check_size(int),
         # Decimal.new/1 would raise beyond 34 digits.
         {decimal, ""} <- Decimal.parse(if(negative?, do: "-", else: "") <> int <> "." <> frac) do
      {:ok, decimal}
    else
      {:error, _message} = error -> error
      _invalid -> {:error, invalid(text)}
    end
  end

  defp invalid(text), do: "Ungültiger Betrag „#{text}“."

  # Only space and no-break space: U+202F and other spaces are not part of a number.
  defp strip_spaces(text), do: String.replace(text, [" ", "\u00A0"], "")

  # "1200,00" is 1200 yen, e.g. after switching an amount from euros to yen.
  defp trim_zeros(frac, decimals) do
    if byte_size(frac) > decimals and String.ends_with?(frac, "0"),
      do: trim_zeros(binary_part(frac, 0, byte_size(frac) - 1), decimals),
      else: frac
  end

  defp check_places(frac, decimals) when byte_size(frac) <= decimals, do: :ok
  defp check_places(_frac, 0), do: {:error, "Dieser Betrag darf keine Nachkommastellen haben."}

  defp check_places(_frac, decimals),
    do: {:error, "Höchstens #{decimals} Nachkommastellen erlaubt."}

  defp check_size(int) when byte_size(int) > 15, do: {:error, "Der Betrag ist zu groß."}
  defp check_size(_int), do: :ok

  defp split_number(text, dot_thousands?) do
    {negative?, digits} =
      case text do
        "-" <> rest -> {true, rest}
        "−" <> rest -> {true, rest}
        "+" <> rest -> {false, rest}
        _unsigned -> {false, text}
      end

    with true <- digits =~ ~r/\A[0-9.,]+\z/ and digits =~ ~r/[0-9]/,
         {:ok, int, frac, thousands} <- separate(digits, dot_thousands?),
         false <- String.contains?(frac, [".", ","]),
         {:ok, int} <- ungroup(int, thousands) do
      {:ok, {negative?, if(int == "", do: "0", else: int), frac}}
    else
      _invalid -> :error
    end
  end

  defp separate(digits, dot_thousands?) do
    dots = count(digits, ".")
    commas = count(digits, ",")

    cond do
      dots > 0 and commas > 0 -> separate_both(digits, dots, commas)
      dots + commas > 1 -> {:ok, digits, "", if(commas > 0, do: ",", else: ".")}
      dots + commas == 1 -> separate_one(digits, dot_thousands?)
      true -> {:ok, digits, "", nil}
    end
  end

  defp separate_both(digits, dots, commas) do
    {int, separator, frac} = split_at_last(digits, [".", ","])

    case separator do
      "." when dots == 1 -> {:ok, int, frac, ","}
      "," when commas == 1 -> {:ok, int, frac, "."}
      _repeated -> :error
    end
  end

  defp separate_one(digits, dot_thousands?) do
    {int, separator, frac} = split_at_last(digits, [".", ","])

    if separator == "." and byte_size(frac) == 3 and dot_thousands? and
         String.trim(int, "0") != "",
       do: {:ok, digits, "", "."},
       else: {:ok, int, frac, nil}
  end

  defp split_at_last(digits, separators) do
    [{position, 1} | _] = digits |> :binary.matches(separators) |> Enum.reverse()

    {binary_part(digits, 0, position), binary_part(digits, position, 1),
     binary_part(digits, position + 1, byte_size(digits) - position - 1)}
  end

  defp ungroup(int, nil), do: if(String.contains?(int, [".", ","]), do: :error, else: {:ok, int})

  defp ungroup(int, thousands) do
    [first | rest] = String.split(int, thousands)

    if first != "" and byte_size(first) <= 3 and Enum.all?(rest, &(byte_size(&1) == 3)),
      do: ungroup(Enum.join([first | rest]), nil),
      else: :error
  end

  defp count(text, char), do: length(:binary.matches(text, char))

  @doc """
  Euro cents as shown: `"1.234,56 €"`, `"−9,99 €"`. Options: `signed: true` puts a plus before
  an inflow (`"+48,75 €"`), `decimals: 0` shows whole euros (`"1.235 €"`).
  """
  @spec euros(integer(), keyword()) :: String.t()
  def euros(cents, opts \\ []) when is_integer(cents),
    do: Setzkasten.Format.money(cents, Keyword.take(opts, [:signed, :decimals]))

  @doc ~s(Minor units of `currency` as shown: `"1.234,56 USD"`, `"123.456 JPY"`; euros as `euros/2`.)
  @spec money(integer(), String.t()) :: String.t()
  def money(minor, currency) when is_integer(minor) do
    if eur?(currency) do
      euros(minor)
    else
      code = normalize_currency(currency)

      Setzkasten.Format.money(minor,
        currency: code,
        currency_display: :code,
        minor_digits: decimals(code)
      )
    end
  end

  @doc """
  Minor units of `currency` as stored text holds them, with a plain space before the unit:
  `"1.234,56 €"`, `"−9,99 €"`, `"100,00 USD"`.
  """
  @spec plain(integer(), String.t()) :: String.t()
  def plain(minor, currency \\ "EUR") when is_integer(minor) do
    unit = if eur?(currency), do: "€", else: normalize_currency(currency)
    amount(minor, currency) <> " " <> unit
  end

  @doc """
  Minor units of `currency` without unit, as shown in a column and as a field holds them:
  `"1.234,56"`, `"−9,99"`, yen `"123.456"`, dinar `"1.234,560"`.
  """
  @spec amount(integer(), String.t()) :: String.t()
  def amount(minor, currency \\ "EUR") when is_integer(minor),
    do: Setzkasten.Format.number(minor, minor_units: true, minor_digits: decimals(currency))

  @doc """
  Euro cents without unit and with their sign, as the register's Betrag shows them: `"+3.180,00"`, `"−88,12"`.
  """
  @spec signed_amount(integer()) :: String.t()
  def signed_amount(cents) when is_integer(cents),
    do: Setzkasten.Format.number(cents, minor_units: true, minor_digits: 2, signed: true)

  @doc ~s(Basis points as a percentage: `"33,33 %"`.)
  @spec format_basis_points(integer()) :: String.t()
  def format_basis_points(points), do: format_minor(points, 2) <> " %"

  @doc """
  `value` in units of 10^-decimals without grouping, as MCP output, CSV exports and Kasse
  percentages write it. Option `:separator` (default `","`).
  """
  @spec format_minor(integer(), non_neg_integer(), keyword()) :: String.t()
  def format_minor(value, decimals, opts \\ []) do
    scale = Integer.pow(10, decimals)
    whole = Integer.to_string(div(abs(value), scale))

    text =
      if decimals > 0 do
        fraction =
          abs(value) |> rem(scale) |> Integer.to_string() |> String.pad_leading(decimals, "0")

        whole <> Keyword.get(opts, :separator, ",") <> fraction
      else
        whole
      end

    if value < 0, do: "-" <> text, else: text
  end

  @doc "A rate in the shortest digits that read back as it, with a comma and never an exponent."
  @spec format_rate(float()) :: String.t()
  def format_rate(rate) when is_float(rate) and rate > 0 do
    {digits, point} = rate |> :erlang.float_to_binary([:short]) |> digits_and_point()

    cond do
      point <= 0 ->
        "0," <> String.duplicate("0", -point) <> digits

      point >= byte_size(digits) ->
        digits <> String.duplicate("0", point - byte_size(digits))

      true ->
        binary_part(digits, 0, point) <>
          "," <> binary_part(digits, point, byte_size(digits) - point)
    end
  end

  def format_rate(_rate), do: ""

  defp digits_and_point(short) do
    {mantissa, exponent} =
      case String.split(short, "e") do
        [mantissa, exponent] -> {mantissa, String.to_integer(exponent)}
        [mantissa] -> {mantissa, 0}
      end

    {int, frac} =
      case String.split(mantissa, ".") do
        [int, "0"] -> {int, ""}
        [int, frac] -> {int, frac}
        [int] -> {int, ""}
      end

    {int <> frac, byte_size(int) + exponent}
  end

  defdelegate normalize_currency(currency), to: Abakus.Currency, as: :normalize
  defdelegate valid_currency?(code), to: Abakus.Currency, as: :valid?

  @doc "Whether `currency` means euros; an empty one does."
  @spec eur?(String.t()) :: boolean()
  def eur?(currency), do: normalize_currency(currency) in ["", "EUR"]

  @doc "The decimal places of `currency`: 0, 2 or 3."
  @spec decimals(String.t()) :: 0 | 2 | 3
  def decimals(currency) do
    code = normalize_currency(currency)

    cond do
      code in @zero_decimals -> 0
      code in @three_decimals -> 3
      true -> 2
    end
  end

  @doc """
  Converts minor units of `currency` at `rate` (units per 1 €) into euro cents, rounding half
  away from zero.
  """
  @spec to_eur_cents(integer(), String.t(), float()) :: {:ok, integer()} | {:error, String.t()}
  def to_eur_cents(minor, currency, rate) when is_number(rate) and rate > 0 do
    cents = minor / :math.pow(10, decimals(currency)) / rate * 100

    if cents >= -@int64_bound and cents < @int64_bound,
      do: {:ok, round(cents)},
      else: {:error, "Der Betrag ist zu groß."}
  end

  def to_eur_cents(_minor, _currency, _rate),
    do: {:error, "Der Wechselkurs muss größer als 0 sein."}
end
