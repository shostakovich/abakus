defmodule Abakus.Bookkeeping.Category do
  @moduledoc """
  A bookkeeping category: one of the Lexoffice categories the owner uses, under its Lexoffice name and group, plus
  the §13b variants of some of them. `euer` is the Kennzahl of its line in the Anlage EÜR (nil for private
  bookings), `vat_return` the Kennzahl of the VAT return it is the base of, which only reverse charge fixes by its
  category; the other Kennzahlen follow from the VAT rate. `vat` is the treatment a new tax line starts with.
  """

  alias Abakus.Bookkeeping.Vat

  @enforce_keys [:key, :name, :group, :kind, :euer, :vat, :lexoffice_id]
  defstruct [:key, :name, :group, :kind, :euer, :vat, :lexoffice_id, vat_return: nil]

  @type t :: %__MODULE__{}

  @eu 46
  @third_country 84

  @all [
    {"revenue", "Einnahmen", "Einnahmen", :income, 112, :rate_19,
     "8f8664a1-fd86-11e1-a21f-0800200c9a66"},
    {"other_revenue", "Sonstige Einnahmen", "Sonstige Einnahmen", :income, 112, :rate_19,
     "cfddcc50-fd86-11e1-a21f-0800200c9a66"},
    {"vat_refund", "Umsatzsteuer-Vorauszahlungen", "Umsatzsteuer-Erstattungen", :income, 141,
     :rate_0, "af1a07f3-8ce4-47dc-8c82-263960c2442d"},
    {"office_equipment", "Betriebs-und Geschäftsausstattung", "Anlagevermögen", :expense, 130,
     :rate_19, "60a5a91b-6b4a-485e-b610-232b423a161d"},
    {"office_furniture", "Büroeinrichtung", "Anlagevermögen", :expense, 130, :rate_19,
     "d0d633ec-dda7-4aa3-867c-96e7a0d97477"},
    {"low_value_assets", "Geringwertige Wirtschaftsgüter", "Anlagevermögen", :expense, 132,
     :rate_19, "1b2d76c2-23a2-48c6-a717-7f9fecf99556"},
    {"other_vehicles", "Sonstige Transportmittel", "Anlagevermögen", :expense, 130, :rate_19,
     "281cd301-6e13-4d27-81c2-30f896e5bf1d"},
    {"bookkeeping_fees", "Buchführungskosten", "Beratung", :expense, 194, :rate_19,
     "2bdc3fd5-3ef3-4732-b315-4fa2c1061994"},
    {"tax_advisor", "Steuerberater", "Beratung", :expense, 194, :rate_19,
     "f48154a1-fd90-11e1-a21f-0800200c9a66"},
    {"vehicle_insurance", "Fahrzeugversicherungen", "Fahrzeug", :expense, 145, :rate_0,
     "9eaf6ff3-fd89-11e1-a21f-0800200c9a66"},
    {"vehicle_repairs", "Inspektion/Reparatur", "Fahrzeug", :expense, 146, :rate_19,
     "9eaf6ff1-fd89-11e1-a21f-0800200c9a66"},
    {"training", "Fortbildung", "Fortbildung", :expense, 281, :rate_19,
     "5bc9acec-85af-48dd-a4c3-9ccc4ea6ac80"},
    {"training_13b_eu", "Fortbildung §13b", "Fortbildung", :expense, 281, @eu,
     "09e90a1b-1aad-43b8-9803-b6fadffaf193"},
    {"training_13b_third_country", "Fortbildung §13b Drittland", "Fortbildung", :expense, 281,
     @third_country, "90fcbad4-d062-4877-8ca2-9b3176782f45"},
    {"seminars", "Seminar/Weiterbildung", "Fortbildung", :expense, 281, :rate_19,
     "16d04a27-fd91-11e1-a21f-0800200c9a66"},
    {"freelancers", "Freelancer/Freie Mitarbeiter", "Fremdleistungen", :expense, 110, :rate_19,
     "205cae71-fd88-11e1-a21f-0800200c9a66"},
    {"external_services", "Fremdleistungen", "Fremdleistungen", :expense, 110, :rate_19,
     "efa82f43-fd85-11e1-a21f-0800200c9a66"},
    {"external_services_13b_eu", "Fremdleistungen §13b", "Fremdleistungen", :expense, 110, @eu,
     "113476af-ac83-4bf2-941d-0daa37022945"},
    {"external_services_13b_third_country", "Fremdleistungen §13b Drittland", "Fremdleistungen",
     :expense, 110, @third_country, "6d49f842-54d9-4ebb-9c24-a25daac76203"},
    {"private", "Privat", "Privat", :expense, nil, :rate_0,
     "efa85653-fd85-11e1-a21f-0800200c9a66"},
    {"private_insurance", "Versicherungen (privat)", "Privat", :expense, nil, :rate_0,
     "328a41b4-58d7-4595-8840-1b96ad398f15"},
    {"travel_tickets", "Bahn-/Flugticket, Mietwagen", "Reisen", :expense, 146, :rate_19,
     "f9f05690-fd89-11e1-a21f-0800200c9a66"},
    {"breakfast", "Frühstück", "Reisen", :expense, 221, :rate_19,
     "4c4f9907-0379-408a-989b-22850d2fbcdc"},
    {"accommodation", "Übernachtungskosten", "Reisen", :expense, 221, :rate_7,
     "f9f05694-fd89-11e1-a21f-0800200c9a66"},
    {"repairs", "Sonstige Reparaturen", "Reparaturen", :expense, 183, :rate_19,
     "d854ed5f-969a-4b5f-b13a-9679648aa988"},
    {"purchases", "Anschaffungen", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "16d04a20-fd91-11e1-a21f-0800200c9a66"},
    {"office_supplies", "Bürobedarf", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "16d04a21-fd91-11e1-a21f-0800200c9a66"},
    {"licenses", "Lizenzen und Konzessionen", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "b49aae5f-4121-4262-b8bd-f49278b66423"},
    {"licenses_13b_eu", "Lizenzen und Konzessionen §13b", "Sonstige Ausgaben", :expense, 183, @eu,
     "587c625c-2a8b-4a0e-88a7-5e058af9f7e9"},
    {"licenses_13b_third_country", "Lizenzen und Konzessionen §13b Drittland",
     "Sonstige Ausgaben", :expense, 183, @third_country, "6d575db0-74e8-433d-a986-27b76ea27f9e"},
    {"postage", "Porto", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "16d04a24-fd91-11e1-a21f-0800200c9a66"},
    {"other_expenses", "Sonstige Ausgaben", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "16d04a28-fd91-11e1-a21f-0800200c9a66"},
    {"maintenance", "Wartungskosten für Hard- und Software", "Sonstige Ausgaben", :expense, 183,
     :rate_19, "9d92c0dc-8cea-4791-ab3b-90f913101d32"},
    {"tools", "Werkzeuge und Kleingeräte", "Sonstige Ausgaben", :expense, 183, :rate_19,
     "d5249d10-fd90-11e1-a21f-0800200c9a66"},
    {"currency_conversion", "Währungsumrechnung", "Sonstige Ausgaben", :expense, 183, :rate_0,
     "207833b2-59fb-4185-b7b3-52ab9b944d59"},
    {"books", "Zeitschriften/Bücher", "Sonstige Ausgaben", :expense, 183, :rate_7,
     "16d04a29-fd91-11e1-a21f-0800200c9a66"},
    {"landline", "Festnetz", "Telekommunikation", :expense, 280, :rate_19,
     "b3a1f840-fd90-11e1-a21f-0800200c9a66"},
    {"internet", "Internet", "Telekommunikation", :expense, 280, :rate_19,
     "b3a1f841-fd90-11e1-a21f-0800200c9a66"},
    {"mobile", "Mobil", "Telekommunikation", :expense, 280, :rate_19,
     "b3a1f842-fd90-11e1-a21f-0800200c9a66"},
    {"telecommunication", "Telekommunikation", "Telekommunikation", :expense, 280, :rate_19,
     "efa82f4b-fd85-11e1-a21f-0800200c9a66"},
    {"vat_payment", "Umsatzsteuer-Vorauszahlungen", "Umsatzsteuer-Vorauszahlungen", :expense, 186,
     :rate_0, "222b6f72-fd92-11e1-a21f-0800200c9a66"},
    {"insurance_contributions", "Beiträge", "Versicherungen (betrieblich)", :expense, 223,
     :rate_0, "f49d88d1-fd88-11e1-a21f-0800200c9a66"},
    {"advertising", "Werbung", "Werbung", :expense, 224, :rate_19,
     "efa82f48-fd85-11e1-a21f-0800200c9a66"},
    {"advertising_13b_eu", "Werbung §13b", "Werbung", :expense, 224, @eu,
     "00d8f5f6-1d8a-40da-96ee-c53b25f37503"},
    {"advertising_13b_third_country", "Werbung §13b Drittland", "Werbung", :expense, 224,
     @third_country, "db55a5ca-8b9e-4c84-9961-dd2110f3b2b6"},
    {"bank_fees", "Nebenkosten des Geldverkehrs", "Zinsen/Gebühren", :expense, 183, :rate_19,
     "16d04a23-fd91-11e1-a21f-0800200c9a66"}
  ]

  @keys Enum.map(@all, &elem(&1, 0))

  @doc "Every category, income first, then the expenses by their Lexoffice group."
  def all, do: Enum.map(@all, &build/1)

  @doc "The category with `key`, or nil."
  def get(key) do
    case List.keyfind(@all, key, 0) do
      nil -> nil
      row -> build(row)
    end
  end

  @doc "The keys of every category."
  def keys, do: @keys

  defp build({key, name, group, kind, euer, vat, lexoffice_id}) do
    {vat, vat_return} = if is_integer(vat), do: {:reverse_charge, vat}, else: {vat, nil}

    %__MODULE__{
      key: key,
      name: name,
      group: group,
      kind: kind,
      euer: euer,
      vat: vat,
      vat_return: vat_return,
      lexoffice_id: lexoffice_id
    }
  end

  @doc "Whether the category is a reverse-charge one under §13b."
  def reverse_charge?(%__MODULE__{vat: vat}), do: vat == :reverse_charge

  @doc "The categories in their Lexoffice groups, in order: `[{group, [category]}]`."
  def grouped do
    all()
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(&{hd(&1).group, &1})
  end

  @doc "Whether the treatment fits the category: reverse charge for a §13b category and only there."
  def fits?(%__MODULE__{} = category, treatment) when is_atom(treatment),
    do:
      reverse_charge?(category) == (treatment == :reverse_charge) and
        treatment in Vat.treatments()
end
