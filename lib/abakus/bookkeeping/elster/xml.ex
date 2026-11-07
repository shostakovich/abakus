defmodule Abakus.Bookkeeping.Elster.Xml do
  @moduledoc """
  A return in ELSTER's XML (ElsterXML v11): the transfer header ERiC sends it under and, as its Nutzdaten, one of

    * the Umsatzsteuer-Voranmeldung of a quarter (Datenart UStVA, `Abakus.Bookkeeping.VatReturn`), by Kennzahl
      (`Kz81`): bases whole euros, taxes euros with a point and two decimals, in ascending order of their Kennzahl;
      one that is zero is left out, Kz 83 never;
    * the Umsatzsteuererklärung of a year (Datenart USt, form E50 with the USt 2A) and the EÜR (Datenart EUER, form
      E77 with the Anlage AVEÜR, `Abakus.Bookkeeping.IncomeStatement`), by ELSTER's field ids (`E3003303`): bases
      whole euros, amounts with a decimal comma, a group only when it holds something. Their Vorsatz names the tax
      number, the year and the sender, their transfer header the state of the tax office. The annual return has no
      field here for sales at other rates (Kz 155 and 156), the AVEÜR lists every asset among the other movable ones.

  The tax office is the first four digits of the tax number in ELSTER's format. Every form is in the schema of its
  year, which ERiC validates it against before sending.
  """

  import Abakus.Xml, only: [element: 2, element: 3]

  alias Abakus.Bookkeeping.{IncomeStatement, Settings, VatReturn}
  alias Abakus.Money

  @test_flag "700000004"

  @on_receipts "2"

  @income_kinds %{self_employment: {"140", "3"}, trade: {"120", "2"}}

  @euer_fields %{
    112 => "E6000401",
    140 => "E6000601",
    141 => "E6000701",
    102 => "E6000801",
    110 => "E6001701",
    130 => "E6002101",
    132 => "E6002301",
    135 => "E6002401",
    280 => "E6003901",
    221 => "E6004004",
    281 => "E6004003",
    194 => "E6004801",
    223 => "E6004402",
    224 => "E6004501",
    185 => "E6005001",
    186 => "E6005101",
    183 => "E6004901",
    145 => "E6005903",
    146 => "E6006003"
  }

  @doc "The Datenart version ERiC processes the return as."
  def datenart_version(%VatReturn{year: year, quarter: quarter}) when quarter in 1..4,
    do: "UStVA_#{year}"

  def datenart_version(%VatReturn{year: year, quarter: nil}), do: "USt_#{year}"
  def datenart_version(%IncomeStatement{year: year}), do: "EUER_#{year}"

  @doc "The Kennzahlen of the Anlage EÜR the EÜR writes, by Kennzahl, without the totals."
  def euer_kennzahlen, do: Map.keys(@euer_fields)

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

    document({"ElsterAnmeldung", "UStVA", nil}, settings, elster_tax_number, nutzdaten, opts)
  end

  @doc "The Umsatzsteuererklärung `vat_return` of a year; arguments and options as `vat_quarter/4`."
  def vat_year(
        %VatReturn{quarter: nil} = vat_return,
        %Settings{} = settings,
        elster_tax_number,
        opts
      ) do
    nutzdaten =
      element("E50", namespace("ust/e50", vat_return.year), [
        element("USt2A", [
          vat_general(settings),
          sales(vat_return),
          reverse_charge(vat_return),
          input_tax(vat_return),
          vat_computation(vat_return)
        ]),
        preamble("50", vat_return.year, settings, elster_tax_number)
      ])

    document(
      {"ElsterErklaerung", "USt", settings.tax_state},
      settings,
      elster_tax_number,
      nutzdaten,
      opts
    )
  end

  @doc "The EÜR `statement` of a year; arguments and options as `vat_quarter/4`."
  def euer(%IncomeStatement{} = statement, %Settings{} = settings, elster_tax_number, opts) do
    amounts = IncomeStatement.kennzahlen(statement)

    nutzdaten =
      element("E77", namespace("euer/e77", statement.year), [
        element("EUER", [
          euer_general(settings),
          euer_income(amounts),
          euer_expenses(amounts),
          profit(amounts)
        ]),
        asset_register(statement.assets),
        preamble("77", statement.year, settings, elster_tax_number)
      ])

    document(
      {"ElsterErklaerung", "EUER", settings.tax_state},
      settings,
      elster_tax_number,
      nutzdaten,
      opts
    )
  end

  defp document({verfahren, datenart, state}, settings, elster_tax_number, nutzdaten, opts) do
    document =
      element("Elster", [{"xmlns", "http://www.elster.de/elsterxml/schema/v11"}], [
        transfer_header({verfahren, datenart, state}, settings, opts),
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

  defp transfer_header({verfahren, datenart, state}, settings, opts) do
    element("TransferHeader", [{"version", "11"}], [
      element("Verfahren", verfahren),
      element("DatenArt", datenart),
      element("Vorgang", "send-Auth"),
      Keyword.get(opts, :test, false) && element("Testmerker", @test_flag),
      state && element("Empfaenger", [{"id", "L"}], [element("Ziel", state)]),
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

  defp namespace(form, year),
    do: [
      {"xmlns", "http://finkonsens.de/elster/elstererklaerung/#{form}/v#{year}"},
      {"version", "#{year}"}
    ]

  defp preamble(subcase, year, settings, elster_tax_number) do
    element("Vorsatz", [
      element("Unterfallart", subcase),
      element("Vorgang", "01"),
      element("StNr", elster_tax_number),
      element("Zeitraum", "#{year}"),
      element("AbsName", String.slice(settings.name, 0, 45)),
      element("AbsStr", String.slice(settings.street, 0, 30)),
      element("AbsPlz", settings.postal_code),
      element("AbsOrt", String.slice(settings.city, 0, 29)),
      element("Copyright", "Abakus"),
      element("OrdNrArt", "S"),
      element("Rueckuebermittlung", [element("Bescheid", "2")])
    ])
  end

  defp vat_general(settings) do
    element("Allg", [
      element("Unternehmen", [
        element("E3000901", String.slice(settings.name, 0, 45)),
        element("Adr", [
          element("E3001101", settings.street),
          element("E3001206", settings.postal_code),
          element("E3001207", settings.city)
        ])
      ]),
      element("Best_Art", [element("E3002203", @on_receipts)])
    ])
  end

  defp sales(vat_return) do
    sales_19 = line(vat_return, :sales_19)
    sales_7 = line(vat_return, :sales_7)

    table(
      "Umsaetze",
      [
        sale("Ums_allg", {"E3003303", "E3003304"}, sales_19),
        sale("Ums_erm", {"E3004401", "E3004402"}, sales_7)
      ],
      element("Ums_Sum", [element("E3006001", comma(sales_19.tax + sales_7.tax))])
    )
  end

  defp sale(_name, _fields, %{base: 0}), do: nil

  defp sale(name, {base_field, tax_field}, line),
    do: element(name, [element(base_field, "#{line.base}"), element(tax_field, comma(line.tax))])

  defp reverse_charge(vat_return) do
    eu = line(vat_return, :reverse_charge_eu)
    other = line(vat_return, :reverse_charge_other)

    table(
      "Ums_13b",
      [
        base_and_tax({"E3102205", "E3102206"}, eu),
        base_and_tax({"E3102503", "E3102504"}, other)
      ],
      element("Ums_13b_Sum", [element("E3102601", comma(eu.tax + other.tax))])
    )
  end

  defp base_and_tax(_fields, %{base: 0, tax: 0}), do: nil

  defp base_and_tax({base_field, tax_field}, line),
    do: [element(base_field, "#{line.base}"), element(tax_field, comma(line.tax))]

  defp input_tax(vat_return) do
    input = line(vat_return, :input).tax
    reverse_charge = line(vat_return, :input_reverse_charge).tax

    table(
      "Abz_VoSt",
      [nonzero("E3006201", input), nonzero("E3006502", reverse_charge)],
      element("Abz_VoSt_Sum", [element("E3006901", comma(input + reverse_charge))])
    )
  end

  defp vat_computation(vat_return) do
    output = line(vat_return, :sales_19).tax + line(vat_return, :sales_7).tax

    reverse_charge =
      line(vat_return, :reverse_charge_eu).tax + line(vat_return, :reverse_charge_other).tax

    input = line(vat_return, :input).tax + line(vat_return, :input_reverse_charge).tax

    element("Berech_USt", [
      element("Tabelle", [
        nonzero("E3009201", output),
        nonzero("E3009502", reverse_charge),
        nonzero("E3009801", output + reverse_charge),
        nonzero("E3009901", input),
        element("E3010201", comma(vat_return.due)),
        element("E3010601", comma(vat_return.due)),
        element("Verbl_USt", [
          element("E3011101", comma(vat_return.due)),
          element("E3011301", comma(vat_return.prepaid))
        ]),
        element("Zahl_Erstatt", [element("E3011401", comma(vat_return.balance))])
      ])
    ])
  end

  defp line(%VatReturn{lines: lines}, key), do: Enum.find(lines, &(&1.key == key))

  defp table(name, rows, sum) do
    case Enum.filter(rows, & &1) do
      [] -> nil
      rows -> element(name, [element("Tabelle", rows ++ [sum])])
    end
  end

  defp euer_general(settings) do
    {legal_form, income_kind} = Map.fetch!(@income_kinds, settings.income_kind)

    element("Allg", [
      element("E6000016", settings.name),
      element("E6000017", settings.business_activity),
      element("E6000602", legal_form),
      element("E6000603", income_kind),
      element("E6000604", "1"),
      element("E6000019", "2")
    ])
  end

  defp euer_income(amounts) do
    element("BEin", [
      sum("USt_StPflicht", 112, amounts),
      sum("USt_Vereinnahmt_Unentgeltl", 140, amounts),
      sum("USt_Erstattet_Verrechnet", 141, amounts),
      sum("Anlagevermoegen", 102, amounts),
      element("GesamtSum", [element("E6001201", comma(amounts[159]))])
    ])
  end

  defp euer_expenses(amounts) do
    element("BAus", [
      sum("Fremdleistung", 110, amounts),
      group("AfA", [
        nonzero(@euer_fields[130], amounts[130]),
        sum("Wirtschaftsgut_geringwertig", 132, amounts),
        group("Weitere_Angabe", [nonzero(@euer_fields[135], amounts[135])])
      ]),
      group("Sonst_unbeschraenkt", [
        sum("Kommunikation", 280, amounts),
        sum("Auswertstaetigkeit", 221, amounts),
        sum("Fortbildung", 281, amounts),
        sum("Rechtsberatung_StB_Buchf", 194, amounts),
        sum("Beitrag_Gebuehr_Abgabe_Versicherung", 223, amounts),
        sum("Werbung", 224, amounts),
        sum("Vorsteuer", 185, amounts),
        sum("USt", 186, amounts),
        sum("Sonst_unbeschr_abziehbar", 183, amounts)
      ]),
      group("KFZ_u_Fahrtkosten", [
        sum("Steuer_Versicherung_Maut", 145, amounts),
        sum("Sonst", 146, amounts)
      ]),
      element("Summe_BAus", [element("E6005301", comma(amounts[199]))])
    ])
  end

  defp profit(amounts) do
    income = amounts[159]
    expenses = amounts[199]

    element("Ermittlung_Gewinn", [
      element("Uebertrag", [
        element("E6005501", comma(income)),
        element("E6005601", comma(expenses))
      ]),
      element("Korrektur_GuV", [element("E6006801", comma(income - expenses))]),
      element("Stpfl_GuV", [
        element("E6007002", comma(income - expenses)),
        element("E6007202", comma(income - expenses))
      ])
    ])
  end

  defp sum(name, kennzahl, amounts) do
    case Map.get(amounts, kennzahl, 0) do
      0 ->
        nil

      cents ->
        element(name, [
          element("Sum", [element(Map.fetch!(@euer_fields, kennzahl), comma(cents))])
        ])
    end
  end

  defp asset_register([]), do: nil

  defp asset_register(assets) do
    element("AVEUER", [
      element("Bewegliche_WG", [
        element("Andere", Enum.map(assets, &asset/1) ++ [asset_sums(assets)]),
        group("GesamtSum", [nonzero("E6007372", Enum.sum_by(assets, & &1.write_off))])
      ])
    ])
  end

  defp asset(asset) do
    element("Einz", [
      element("E6007351", String.slice(asset.name, 0, 100)),
      element("E6007366", Calendar.strftime(asset.purchased_on, "%d.%m.%Y")),
      element("E6007352", comma(asset.net)),
      element("E6007354", comma(asset.start)),
      nonzero("E6007360", asset.write_off),
      nonzero("E6007362", asset.remaining),
      element("E6007364", comma(asset.end))
    ])
  end

  defp asset_sums(assets) do
    total = &Enum.sum_by(assets, &1)

    element("Sum", [
      element("E6007353", comma(total.(& &1.net))),
      nonzero("E6007355", total.(& &1.start)),
      nonzero("E6007361", total.(& &1.write_off)),
      nonzero("E6007363", total.(& &1.remaining)),
      element("E6007365", comma(total.(& &1.end)))
    ])
  end

  defp group(name, children) do
    case Enum.filter(children, & &1) do
      [] -> nil
      children -> element(name, children)
    end
  end

  defp nonzero(_field, cents) when cents in [0, nil], do: nil
  defp nonzero(field, cents), do: element(field, comma(cents))

  @doc "The Voranmeldung's Kennzahlen as ELSTER writes them, in ascending order."
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
          do: {kennzahl, point(cents)}

    due =
      for %{kennzahl: kennzahl, tax: cents} <- totals,
          kennzahl != nil,
          do: {kennzahl, point(cents)}

    Enum.sort_by(bases ++ taxes ++ due, &elem(&1, 0))
  end

  defp comma(cents), do: Money.format_minor(cents, 2)

  defp point(cents), do: Money.format_minor(cents, 2, separator: ".")

  defp product_version, do: :abakus |> Application.spec(:vsn) |> to_string()
end
