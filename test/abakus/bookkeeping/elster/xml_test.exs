defmodule Abakus.Bookkeeping.Elster.XmlTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Category, FixedAsset, IncomeStatement, Settings, VatReturn}
  alias Abakus.Bookkeeping.Elster.Xml

  @settings %Settings{
    name: "Robert <Beispiel> & Co",
    street: "Lindenallee 4",
    postal_code: "10115",
    city: "Berlin",
    tax_state: "BE",
    business_activity: "Softwareentwicklung",
    income_kind: :self_employment
  }

  @opts [vendor_id: "74931", test: true, created_on: ~D[2028-03-10]]

  defp entry(date, amount, category, vat),
    do: %{date: date, amount: amount, category: Category.get(category), vat: vat}

  defp vat_return(entries), do: VatReturn.quarter(2027, 1, entries)

  defp xml(vat_return, opts \\ []) do
    Xml.vat_quarter(
      vat_return,
      @settings,
      "1130012345678",
      Keyword.merge([vendor_id: "74931", test: true, created_on: ~D[2027-04-10]], opts)
    )
  end

  test "writes the Voranmeldung of a quarter under its year's schema, as ERiC sends it" do
    xml = xml(vat_return([entry(~D[2027-01-20], 119_000, "revenue", :rate_19)]))
    version = :abakus |> Application.spec(:vsn) |> to_string()

    assert xml ==
             ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <>
               ~s(<Elster xmlns="http://www.elster.de/elsterxml/schema/v11">) <>
               ~s(<TransferHeader version="11"><Verfahren>ElsterAnmeldung</Verfahren><DatenArt>UStVA</DatenArt>) <>
               ~s(<Vorgang>send-Auth</Vorgang><Testmerker>700000004</Testmerker><HerstellerID>74931</HerstellerID>) <>
               ~s(<DatenLieferant>Robert &lt;Beispiel&gt; &amp; Co, Lindenallee 4, 10115 Berlin</DatenLieferant>) <>
               ~s(<Datei><Verschluesselung>CMSEncryptedData</Verschluesselung><Kompression>GZIP</Kompression>) <>
               ~s(<TransportSchluessel></TransportSchluessel></Datei></TransferHeader>) <>
               ~s(<DatenTeil><Nutzdatenblock><NutzdatenHeader version="11"><NutzdatenTicket>1</NutzdatenTicket>) <>
               ~s(<Empfaenger id="F">1130</Empfaenger><Hersteller><ProduktName>Abakus</ProduktName>) <>
               ~s(<ProduktVersion>#{version}</ProduktVersion></Hersteller></NutzdatenHeader><Nutzdaten>) <>
               ~s(<Anmeldungssteuern xmlns="http://finkonsens.de/elster/elsteranmeldung/ustva/v2027" version="2027">) <>
               ~s(<Erstellungsdatum>20270410</Erstellungsdatum><DatenLieferant>) <>
               ~s(<Name>Robert &lt;Beispiel&gt; &amp; Co</Name><Strasse>Lindenallee 4</Strasse><PLZ>10115</PLZ>) <>
               ~s(<Ort>Berlin</Ort></DatenLieferant><Steuerfall><Umsatzsteuervoranmeldung><Jahr>2027</Jahr>) <>
               ~s(<Zeitraum>41</Zeitraum><Steuernummer>1130012345678</Steuernummer><Kz09>74931</Kz09>) <>
               ~s(<Kz81>1000</Kz81><Kz83>190.00</Kz83></Umsatzsteuervoranmeldung></Steuerfall>) <>
               ~s(</Anmeldungssteuern></Nutzdaten></Nutzdatenblock></DatenTeil></Elster>)
  end

  test "carries no test flag with a vendor id of its own" do
    xml = xml(vat_return([]), vendor_id: "12345", test: false)

    refute xml =~ "Testmerker"
    assert xml =~ "<HerstellerID>12345</HerstellerID>"
    assert xml =~ "<Kz09>12345</Kz09>"
  end

  test "writes bases in whole euros and taxes with two decimals, ascending, without zeros but Kz 83" do
    vat_return =
      vat_return([
        entry(~D[2027-01-20], 119_000, "revenue", :rate_19),
        entry(~D[2027-02-03], 53_500, "revenue", :rate_7),
        entry(~D[2027-02-10], -10_000, "licenses_13b_eu", :reverse_charge),
        entry(~D[2027-01-05], -595_000, "internet", :rate_19)
      ])

    assert Xml.fields(vat_return) == [
             {46, "100"},
             {47, "19.00"},
             {66, "950.00"},
             {67, "19.00"},
             {81, "1000"},
             {83, "-725.00"},
             {86, "500"}
           ]

    assert Xml.fields(vat_return([])) == [{83, "0.00"}]
  end

  test "names the quarter by 41 to 44 and the Datenart by its year" do
    vat_return = VatReturn.quarter(2026, 4, [])

    assert xml(vat_return) =~ "<Jahr>2026</Jahr><Zeitraum>44</Zeitraum>"
    assert Xml.datenart_version(vat_return) == "UStVA_2026"
  end

  describe "the Umsatzsteuererklärung of a year" do
    test "goes as form E50 of its year, to the state of the tax office" do
      vat_return =
        VatReturn.year(2027, [
          entry(~D[2027-01-20], 119_000, "revenue", :rate_19),
          entry(~D[2027-02-05], -11_900, "internet", :rate_19)
        ])

      xml = Xml.vat_year(vat_return, @settings, "1130012345678", @opts)

      assert xml =~
               ~s(<TransferHeader version="11"><Verfahren>ElsterErklaerung</Verfahren><DatenArt>USt</DatenArt>) <>
                 ~s(<Vorgang>send-Auth</Vorgang><Testmerker>700000004</Testmerker>) <>
                 ~s(<Empfaenger id="L"><Ziel>BE</Ziel></Empfaenger><HerstellerID>74931</HerstellerID>)

      assert xml =~ ~s(<Empfaenger id="F">1130</Empfaenger>)

      assert xml =~
               ~s(<Nutzdaten><E50 xmlns="http://finkonsens.de/elster/elstererklaerung/ust/e50/v2027" version="2027">) <>
                 ~s(<USt2A><Allg><Unternehmen><E3000901>Robert &lt;Beispiel&gt; &amp; Co</E3000901>) <>
                 ~s(<Adr><E3001101>Lindenallee 4</E3001101><E3001206>10115</E3001206><E3001207>Berlin</E3001207>) <>
                 ~s(</Adr></Unternehmen><Best_Art><E3002203>2</E3002203></Best_Art></Allg>) <>
                 ~s(<Umsaetze><Tabelle><Ums_allg><E3003303>1000</E3003303><E3003304>190,00</E3003304></Ums_allg>) <>
                 ~s(<Ums_Sum><E3006001>190,00</E3006001></Ums_Sum></Tabelle></Umsaetze>) <>
                 ~s(<Abz_VoSt><Tabelle><E3006201>19,00</E3006201><Abz_VoSt_Sum><E3006901>19,00</E3006901>) <>
                 ~s(</Abz_VoSt_Sum></Tabelle></Abz_VoSt><Berech_USt><Tabelle><E3009201>190,00</E3009201>) <>
                 ~s(<E3009801>190,00</E3009801><E3009901>19,00</E3009901><E3010201>171,00</E3010201>) <>
                 ~s(<E3010601>171,00</E3010601><Verbl_USt><E3011101>171,00</E3011101><E3011301>171,00</E3011301>) <>
                 ~s(</Verbl_USt><Zahl_Erstatt><E3011401>0,00</E3011401></Zahl_Erstatt></Tabelle></Berech_USt>) <>
                 ~s(</USt2A><Vorsatz><Unterfallart>50</Unterfallart><Vorgang>01</Vorgang>) <>
                 ~s(<StNr>1130012345678</StNr><Zeitraum>2027</Zeitraum><AbsName>Robert &lt;Beispiel&gt; &amp; Co</AbsName>) <>
                 ~s(<AbsStr>Lindenallee 4</AbsStr><AbsPlz>10115</AbsPlz><AbsOrt>Berlin</AbsOrt>) <>
                 ~s(<Copyright>Abakus</Copyright><OrdNrArt>S</OrdNrArt>) <>
                 ~s(<Rueckuebermittlung><Bescheid>2</Bescheid></Rueckuebermittlung></Vorsatz></E50></Nutzdaten>)

      assert Xml.datenart_version(vat_return) == "USt_2027"
    end

    test "declares reverse charge as owed and deducted, without sales it has not" do
      vat_return =
        VatReturn.year(2027, [entry(~D[2027-02-10], -10_000, "licenses_13b_eu", :reverse_charge)])

      xml = Xml.vat_year(vat_return, @settings, "1130012345678", @opts)

      refute xml =~ "Umsaetze"

      assert xml =~
               ~s(<Ums_13b><Tabelle><E3102205>100</E3102205><E3102206>19,00</E3102206>) <>
                 ~s(<Ums_13b_Sum><E3102601>19,00</E3102601></Ums_13b_Sum></Tabelle></Ums_13b>) <>
                 ~s(<Abz_VoSt><Tabelle><E3006502>19,00</E3006502><Abz_VoSt_Sum><E3006901>19,00</E3006901>) <>
                 ~s(</Abz_VoSt_Sum></Tabelle></Abz_VoSt><Berech_USt><Tabelle><E3009502>19,00</E3009502>) <>
                 ~s(<E3009801>19,00</E3009801><E3009901>19,00</E3009901><E3010201>0,00</E3010201>)
    end
  end

  describe "the EÜR of a year" do
    defp statement(entries, assets), do: IncomeStatement.year(2027, entries, assets)

    @notebook %FixedAsset{
      name: "Notebook",
      purchased_on: ~D[2027-04-10],
      net: 240_000,
      useful_life: 3,
      disposal: nil
    }

    test "goes as form E77 with the Anlage AVEÜR, to the state of the tax office" do
      statement =
        statement(
          [
            entry(~D[2027-01-20], 119_000, "revenue", :rate_19),
            entry(~D[2027-02-05], -11_900, "internet", :rate_19)
          ],
          [@notebook]
        )

      xml = Xml.euer(statement, @settings, "1130012345678", @opts)

      assert xml =~
               ~s(<Verfahren>ElsterErklaerung</Verfahren><DatenArt>EUER</DatenArt><Vorgang>send-Auth</Vorgang>) <>
                 ~s(<Testmerker>700000004</Testmerker><Empfaenger id="L"><Ziel>BE</Ziel></Empfaenger>)

      assert xml =~
               ~s(<Nutzdaten><E77 xmlns="http://finkonsens.de/elster/elstererklaerung/euer/e77/v2027" version="2027">) <>
                 ~s(<EUER><Allg><E6000016>Robert &lt;Beispiel&gt; &amp; Co</E6000016>) <>
                 ~s(<E6000017>Softwareentwicklung</E6000017><E6000602>140</E6000602><E6000603>3</E6000603>) <>
                 ~s(<E6000604>1</E6000604><E6000019>2</E6000019></Allg>) <>
                 ~s(<BEin><USt_StPflicht><Sum><E6000401>1000,00</E6000401></Sum></USt_StPflicht>) <>
                 ~s(<USt_Vereinnahmt_Unentgeltl><Sum><E6000601>190,00</E6000601></Sum></USt_Vereinnahmt_Unentgeltl>) <>
                 ~s(<GesamtSum><E6001201>1190,00</E6001201></GesamtSum></BEin>) <>
                 ~s(<BAus><AfA><E6002101>600,00</E6002101></AfA><Sonst_unbeschraenkt>) <>
                 ~s(<Kommunikation><Sum><E6003901>100,00</E6003901></Sum></Kommunikation>) <>
                 ~s(<Vorsteuer><Sum><E6005001>19,00</E6005001></Sum></Vorsteuer></Sonst_unbeschraenkt>) <>
                 ~s(<Summe_BAus><E6005301>719,00</E6005301></Summe_BAus></BAus>) <>
                 ~s(<Ermittlung_Gewinn><Uebertrag><E6005501>1190,00</E6005501><E6005601>719,00</E6005601>) <>
                 ~s(</Uebertrag><Korrektur_GuV><E6006801>471,00</E6006801></Korrektur_GuV>) <>
                 ~s(<Stpfl_GuV><E6007002>471,00</E6007002><E6007202>471,00</E6007202></Stpfl_GuV>) <>
                 ~s(</Ermittlung_Gewinn></EUER>) <>
                 ~s(<AVEUER><Bewegliche_WG><Andere><Einz><E6007351>Notebook</E6007351>) <>
                 ~s(<E6007366>10.04.2027</E6007366><E6007352>2400,00</E6007352><E6007354>2400,00</E6007354>) <>
                 ~s(<E6007360>600,00</E6007360><E6007364>1800,00</E6007364></Einz>) <>
                 ~s(<Sum><E6007353>2400,00</E6007353><E6007355>2400,00</E6007355><E6007361>600,00</E6007361>) <>
                 ~s(<E6007365>1800,00</E6007365></Sum></Andere><GesamtSum><E6007372>600,00</E6007372></GesamtSum>) <>
                 ~s(</Bewegliche_WG></AVEUER><Vorsatz><Unterfallart>77</Unterfallart><Vorgang>01</Vorgang>) <>
                 ~s(<StNr>1130012345678</StNr><Zeitraum>2027</Zeitraum>)

      assert Xml.datenart_version(statement) == "EUER_2027"
    end

    test "writes a trade's legal form and leaves out the asset register without depreciated assets" do
      xml =
        Xml.euer(statement([], []), %{@settings | income_kind: :trade}, "1130012345678", @opts)

      assert xml =~ "<E6000602>120</E6000602><E6000603>2</E6000603>"
      assert xml =~ "<GesamtSum><E6001201>0,00</E6001201></GesamtSum>"
      refute xml =~ "AVEUER"
      refute xml =~ "<AfA>"
    end

    test "has a field for every line of the EÜR" do
      assert Enum.sort(Xml.euer_kennzahlen()) ==
               Enum.sort(
                 IncomeStatement.income_kennzahlen() ++ IncomeStatement.expense_kennzahlen()
               )
    end
  end
end
