defmodule Abakus.FileImport.KontistTest do
  use ExUnit.Case, async: true

  alias Abakus.FileImport.Kontist

  @header ~s("Buchungsdatum";"Wertstellungsdatum";"Transaktionstyp";"Empfänger";"Betrag";"IBAN";) <>
            ~s("Verwendungszweck";"end_to_end_id";"Buchungsstatus";"Kategorie";"Persönliche Notiz")

  defp fixture(name), do: File.read!("test/fixtures/kontist/#{name}")

  defp transactions(rows, header \\ @header) do
    {:ok, [statement]} = Kontist.parse(Enum.join([header | rows], "\n"))
    statement.transactions
  end

  test "reads the export as one statement of the account Kontist, without pending bookings" do
    assert {:ok, [statement]} = Kontist.parse(fixture("geschaeftskonto_2026-09.csv"))

    assert %{bank_id: nil, acct_id: "Kontist", ledger_balance: nil} = statement

    assert [withdrawal, fare, second_fare, software, invoice] = statement.transactions

    assert withdrawal == %{
             fitid: "2026-09-30 -150000 erika mustermann",
             date: ~D[2026-09-30],
             amount: -150_000,
             name: "Erika Mustermann",
             memo: "Privatentnahme September"
           }

    assert %{fitid: "2026-09-15 -450 bahn beispiel", memo: nil} = fare
    assert second_fare.fitid == "2026-09-15 -450 bahn beispiel 2"
    assert software.memo == "Rechnung 4711; Abo September"
    assert invoice.amount == 238_000
  end

  test "reads quoted fields with doubled quotes and line breaks, and unquoted ones" do
    assert [%{name: ~s(Laden "Ecke"), memo: "Zeile 1\nZeile 2"}, %{name: "Kiosk", amount: -100}] =
             transactions([
               ~s("2026-09-01";;;"Laden ""Ecke""";"-1,00";;"Zeile 1\nZeile 2";;"Gebucht";;),
               "2026-09-02;;;Kiosk;-1,00;;;;Gebucht;;"
             ])
  end

  test "reads comma-separated exports with German dates, CRLF and a byte order mark" do
    content =
      "﻿Buchungsdatum,Empfänger,Betrag,Verwendungszweck\r\n" <>
        ~s(02.09.2026,Kiosk,"-1,50",Zeitung\r\n)

    assert {:ok, [%{transactions: [%{date: ~D[2026-09-02], amount: -150, memo: "Zeitung"}]}]} =
             Kontist.parse(content)
  end

  test "reads a Latin-1 file" do
    content =
      :unicode.characters_to_binary(
        "Buchungsdatum;Empfänger;Betrag;Verwendungszweck\n2026-09-02;Bäckerei;-1,00;\n",
        :utf8,
        :latin1
      )

    assert {:ok, [%{transactions: [%{name: "Bäckerei"}]}]} = Kontist.parse(content)
  end

  test "skips blank lines and takes an export without bookings" do
    assert transactions(["", "2026-09-02;;;Kiosk;-1,00;;;;Gebucht;;", ""]) |> length() == 1
    assert transactions([]) == []
  end

  test "names the booking it cannot read" do
    assert Kontist.parse(
             @header <> "\n2026-09-02;;;Kiosk;-1,00;;;;;;\n2026-13-02;;;Kiosk;-1,00;;;;;;"
           ) ==
             {:error, "Buchung 2 hat kein gültiges Buchungsdatum."}

    assert Kontist.parse(@header <> "\n2026-09-02;;;Kiosk;viel;;;;;;") ==
             {:error, "Buchung 1 hat keinen gültigen Betrag."}
  end

  test "tells an export from other files" do
    assert Kontist.export?(fixture("geschaeftskonto_2026-09.csv"))
    refute Kontist.export?("Datum;Betrag\n2026-09-01;1,00")
    refute Kontist.export?("")
    refute Kontist.export?(File.read!("test/fixtures/ofx/girokonto_2026-09.ofx"))

    assert Kontist.parse("Datum;Betrag") == {:error, "Die Datei ist kein CSV-Export von Kontist."}
    assert Kontist.parse("") == {:error, "Die Datei ist kein CSV-Export von Kontist."}
  end
end
