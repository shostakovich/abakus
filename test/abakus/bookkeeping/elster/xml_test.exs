defmodule Abakus.Bookkeeping.Elster.XmlTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Category, Settings, VatReturn}
  alias Abakus.Bookkeeping.Elster.Xml

  @settings %Settings{
    name: "Robert <Beispiel> & Co",
    street: "Lindenallee 4",
    postal_code: "10115",
    city: "Berlin"
  }

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
end
