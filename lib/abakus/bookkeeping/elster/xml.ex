defmodule Abakus.Bookkeeping.Elster.Xml do
  @moduledoc """
  A return in ELSTER's XML (ElsterXML v11): the transfer header ERiC sends it under, and as its Nutzdaten the
  Umsatzsteuer-Voranmeldung of a quarter (`Abakus.Bookkeeping.VatReturn`) in the schema of its year. Bases are whole
  euros, taxes euros with a point and two decimals, in ascending order of their Kennzahl; one that is zero is left
  out, Kz 83 never. The tax office is the first four digits of the tax number in ELSTER's format.
  """

  alias Abakus.Bookkeeping.{Settings, VatReturn}

  @test_flag "700000004"

  @doc "The Datenart version ERiC processes the return of `vat_return` as."
  def datenart_version(%VatReturn{year: year, quarter: quarter}) when quarter in 1..4,
    do: "UStVA_#{year}"

  @doc """
  The Voranmeldung `vat_return` of the owner of `settings`, whose tax number is `elster_tax_number` in ELSTER's
  format. Options: `vendor_id`, `test` for the test flag, and `created_on`.
  """
  def vat_quarter(
        %VatReturn{quarter: quarter} = vat_return,
        %Settings{} = settings,
        elster_tax_number,
        opts
      )
      when quarter in 1..4 do
    nutzdaten =
      element(
        "Anmeldungssteuern",
        [
          {"xmlns", "http://finkonsens.de/elster/elsteranmeldung/ustva/v#{vat_return.year}"},
          {"version", "#{vat_return.year}"}
        ],
        [
          element(
            "Erstellungsdatum",
            Calendar.strftime(Keyword.fetch!(opts, :created_on), "%Y%m%d")
          ),
          element("DatenLieferant", [
            element("Name", String.slice(settings.name, 0, 45)),
            element("Strasse", String.slice(settings.street, 0, 30)),
            element("PLZ", settings.postal_code),
            element("Ort", String.slice(settings.city, 0, 30))
          ]),
          element("Steuerfall", [
            element(
              "Umsatzsteuervoranmeldung",
              [
                element("Jahr", "#{vat_return.year}"),
                element("Zeitraum", "4#{quarter}"),
                element("Steuernummer", elster_tax_number),
                element("Kz09", Keyword.fetch!(opts, :vendor_id))
              ] ++
                for({kennzahl, value} <- fields(vat_return), do: element("Kz#{kennzahl}", value))
            )
          ])
        ]
      )

    document =
      element("Elster", [{"xmlns", "http://www.elster.de/elsterxml/schema/v11"}], [
        transfer_header(settings, opts),
        element("DatenTeil", [
          element("Nutzdatenblock", [
            element("NutzdatenHeader", [{"version", "11"}], [
              element("NutzdatenTicket", "1"),
              element("Empfaenger", [{"id", "F"}], String.slice(elster_tax_number, 0, 4)),
              element("Hersteller", [
                element("ProduktName", "Abakus"),
                element("ProduktVersion", product_version())
              ])
            ]),
            element("Nutzdaten", [nutzdaten])
          ])
        ])
      ])

    IO.iodata_to_binary([~s(<?xml version="1.0" encoding="UTF-8"?>\n), document])
  end

  defp transfer_header(settings, opts) do
    element("TransferHeader", [{"version", "11"}], [
      element("Verfahren", "ElsterAnmeldung"),
      element("DatenArt", "UStVA"),
      element("Vorgang", "send-Auth"),
      Keyword.get(opts, :test, false) && element("Testmerker", @test_flag),
      element("HerstellerID", Keyword.fetch!(opts, :vendor_id)),
      element(
        "DatenLieferant",
        "#{settings.name}, #{settings.street}, #{settings.postal_code} #{settings.city}"
      ),
      element("Datei", [
        element("Verschluesselung", "CMSEncryptedData"),
        element("Kompression", "GZIP"),
        element("TransportSchluessel", [])
      ])
    ])
  end

  @doc "The return's Kennzahlen as ELSTER writes them, in ascending order."
  def fields(%VatReturn{lines: lines, totals: totals}) do
    bases =
      for %{base_kennzahl: kennzahl, base: euros} <- lines,
          kennzahl != nil,
          euros != 0,
          do: {kennzahl, Integer.to_string(euros)}

    taxes =
      for %{tax_kennzahl: kennzahl, tax: cents} <- lines,
          kennzahl != nil,
          cents != 0,
          do: {kennzahl, decimal(cents)}

    due =
      for %{kennzahl: kennzahl, tax: cents} <- totals,
          kennzahl != nil,
          do: {kennzahl, decimal(cents)}

    Enum.sort_by(bases ++ taxes ++ due, &elem(&1, 0))
  end

  defp decimal(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)
    "#{sign}#{div(cents, 100)}.#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"
  end

  defp product_version, do: :abakus |> Application.spec(:vsn) |> to_string()

  defp element(name, attributes \\ [], content)

  defp element(name, attributes, content) when is_list(content) do
    ["<", name, attributes(attributes), ">", Enum.filter(content, & &1), "</", name, ">"]
  end

  defp element(name, attributes, text) when is_binary(text),
    do: ["<", name, attributes(attributes), ">", escape(text), "</", name, ">"]

  defp attributes(attributes),
    do: for({key, value} <- attributes, do: [" ", key, ~s(="), escape(value), ~s(")])

  defp escape(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
