defmodule Abakus.Bookkeeping.Lexoffice.Records do
  @moduledoc """
  Lexoffice's JSON as Abakus's records: a contact as a customer's attributes, an invoice as an invoice's, with
  Lexoffice's amounts in cents. An invoice's counter is what follows the year in its number, 0 for a number of
  another form. A position's unit is read from its name, a piece for one Abakus does not know; text lines are left
  out. The sender is unknown, as Lexoffice's invoice does not name it; the original PDF does.
  """

  alias Abakus.Bookkeeping.{Party, Position}

  @rates %{19 => :rate_19, 16 => :rate_16, 7 => :rate_7}

  @units %{
    "stunde" => "HUR",
    "stunden" => "HUR",
    "std." => "HUR",
    "h" => "HUR",
    "tag" => "DAY",
    "tage" => "DAY",
    "monat" => "MON",
    "monate" => "MON",
    "pauschal" => "LS",
    "pauschale" => "LS"
  }

  @doc "Whether the contact is a customer, which invoices go to."
  def customer?(contact),
    do: is_map(contact["roles"]) and Map.has_key?(contact["roles"], "customer")

  @doc "The attributes of the customer of a contact."
  def customer(contact) do
    address = List.first(get_in(contact, ["addresses", "billing"]) || []) || %{}

    %{
      lexoffice_id: contact["id"],
      name: contact_name(contact),
      street: address["street"],
      postal_code: address["zip"],
      city: address["city"],
      country: address["countryCode"] || "DE",
      vat_id: present(get_in(contact, ["company", "vatRegistrationId"]))
    }
  end

  defp contact_name(%{"company" => %{"name" => name}}), do: present(name)

  defp contact_name(%{"person" => person}) when is_map(person),
    do: present(Enum.join(Enum.reject([person["firstName"], person["lastName"]], &blank?/1), " "))

  defp contact_name(_contact), do: nil

  @doc """
  The attributes of an invoice, with `:contact_id`, the id of its contact if it has one; without its payment, see
  `status/2`, and its PDF. `{:error, reason}` in German for one Abakus cannot take over as it is.
  """
  def invoice(json) do
    with {:ok, date} <- required_day(json["voucherDate"]),
         {:ok, vat} <- vat(json),
         {:ok, amounts} <- amounts(json["totalPrice"]),
         {:ok, positions} <- positions(json["lineItems"] || []) do
      {from, to} = period(json["shippingConditions"] || %{}, date)
      address = json["address"] || %{}

      {:ok,
       Map.merge(amounts, %{
         lexoffice_id: json["id"],
         contact_id: address["contactId"],
         number: json["voucherNumber"],
         counter: counter(json["voucherNumber"]),
         date: date,
         due_date: day(json["dueDate"]) || date,
         service_from: from,
         service_to: to,
         vat: vat,
         positions: positions,
         sender: %Party{country: nil},
         recipient: %Party{
           name: address["name"],
           street: address["street"],
           postal_code: address["zip"],
           city: address["city"],
           country: address["countryCode"] || "DE"
         }
       })}
    end
  end

  @doc "The counter of an invoice number, what follows the year: 125 for `2026125`, 0 for another form."
  def counter(number) do
    case Regex.run(~r/^\d{4}(\d+)$/, number || "") do
      [_number, digits] -> String.to_integer(digits)
      nil -> 0
    end
  end

  defp required_day(value) do
    case day(value) do
      nil -> {:error, "ohne Rechnungsdatum"}
      date -> {:ok, date}
    end
  end

  # Lexoffice writes a day as its local midnight with the offset, so the day is the first ten characters.
  defp day(<<day::binary-size(10), _rest::binary>>) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp day(_none), do: nil

  defp vat(json) do
    tax_type = get_in(json, ["taxConditions", "taxType"])

    rates =
      for item <- json["lineItems"] || [],
          item["type"] != "text",
          uniq: true,
          do: percent(get_in(item, ["unitPrice", "taxRatePercentage"]))

    case {tax_type, rates} do
      {"intraCommunitySupply", _rates} ->
        {:ok, :reverse_charge}

      {type, [rate]} when type in ["net", "gross"] and is_map_key(@rates, rate) ->
        {:ok, @rates[rate]}

      {type, [rate]} when type in ["net", "gross"] ->
        {:error, "mit #{rate} % Umsatzsteuer"}

      {type, [_rate | _more]} when type in ["net", "gross"] ->
        {:error, "mit mehreren Steuersätzen"}

      {type, _rates} ->
        {:error, "mit der Steuerart „#{type}“"}
    end
  end

  defp percent(rate) do
    case to_decimal(rate) do
      nil -> nil
      decimal -> decimal |> Decimal.round(0) |> Decimal.to_integer()
    end
  end

  defp amounts(%{} = total) do
    case Enum.map(~w(totalNetAmount totalTaxAmount totalGrossAmount), &cents(total[&1])) do
      [net, vat, gross] when is_integer(net) and is_integer(vat) and is_integer(gross) ->
        {:ok, %{net: net, vat_amount: vat, total: gross}}

      _missing ->
        {:error, "ohne Beträge"}
    end
  end

  defp amounts(_none), do: {:error, "ohne Beträge"}

  defp positions(items) do
    items
    |> Enum.reject(&(&1["type"] == "text"))
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, positions} ->
      case position(item) do
        {:ok, position} -> {:cont, {:ok, [position | positions]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, positions} -> {:ok, Enum.reverse(positions)}
      error -> error
    end)
  end

  defp position(item) do
    with price when is_integer(price) <- cents(get_in(item, ["unitPrice", "netAmount"])),
         %Decimal{} = quantity <- to_decimal(item["quantity"]) do
      {:ok,
       %Position{
         description: description(item),
         quantity: quantity,
         unit: Map.get(@units, String.downcase(item["unitName"] || ""), "C62"),
         unit_price: price
       }}
    else
      _missing -> {:error, "mit einer Position ohne Preis oder Menge"}
    end
  end

  defp description(item),
    do: [item["name"], item["description"]] |> Enum.reject(&blank?/1) |> Enum.join("\n")

  defp period(%{"shippingType" => type} = shipping, date)
       when type in ["serviceperiod", "deliveryperiod"] do
    case {day(shipping["shippingDate"]), day(shipping["shippingEndDate"])} do
      {%Date{} = from, %Date{} = to} -> {from, to}
      _missing -> {date, date}
    end
  end

  defp period(shipping, date) do
    case day(shipping["shippingDate"]) do
      nil -> {date, date}
      day -> {day, day}
    end
  end

  @doc """
  Whether Lexoffice saw the invoice paid, and on which day, or voided, from the invoice and its `payments`, `nil`
  when it has none: the day it was paid in full, else its last payment, else the invoice's date.
  """
  def status(json, payments) do
    case json["voucherStatus"] do
      "voided" ->
        %{paid_on: nil, voided: true}

      status when status in ["paid", "paidoff"] ->
        %{paid_on: paid_on(json, payments), voided: false}

      _open ->
        %{paid_on: nil, voided: false}
    end
  end

  defp paid_on(json, payments) do
    payments = payments || %{}

    last_payment =
      (payments["paymentItems"] || [])
      |> Enum.map(&day(&1["postingDate"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(Date, fn -> nil end)

    day(payments["paidDate"]) || last_payment || day(json["voucherDate"])
  end

  @doc "Lexoffice's amount in euros, a JSON number, in cents."
  def cents(amount) do
    case to_decimal(amount) do
      nil ->
        nil

      decimal ->
        decimal |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()
    end
  end

  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(_value), do: nil

  defp present(value), do: if(blank?(value), do: nil, else: String.trim(value))

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
