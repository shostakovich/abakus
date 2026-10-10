defmodule Abakus.FileImport.OFXTest do
  use ExUnit.Case, async: true

  alias Abakus.FileImport.OFX

  defp fixture(name), do: File.read!("test/fixtures/ofx/#{name}")

  defp sgml(statement) do
    """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102
    ENCODING:UTF-8

    <OFX>
    <BANKMSGSRSV1><STMTTRNRS><STMTRS>
    <CURDEF>EUR
    <BANKACCTFROM><BANKID>10020030<ACCTID>123</BANKACCTFROM>
    #{statement}
    </STMTRS></STMTTRNRS></BANKMSGSRSV1>
    </OFX>
    """
  end

  defp transaction(fields) do
    "<BANKTRANLIST><STMTTRN>#{fields}</STMTTRN></BANKTRANLIST>"
  end

  test "reads an SGML OFX 1.x statement as MoneyMoney writes it" do
    assert {:ok, [statement]} = OFX.parse(fixture("girokonto_2026-09.ofx"))

    assert statement.bank_id == "10020030"
    assert statement.acct_id == "DE02100200300000004711"
    assert statement.ledger_balance == %{amount: 242_323, date: ~D[2026-09-30]}

    assert [salary, bakery, _market, library] = statement.transactions

    assert salary == %{
             fitid: "MM-0001",
             date: ~D[2026-09-01],
             amount: 250_000,
             name: "Arbeitgeber Muster GmbH",
             memo: "Gehalt September"
           }

    assert bakery.name == "Bäckerei Korn"
    assert bakery.amount == -640
    assert library.memo == nil
  end

  test "reads an XML OFX 2.x credit card statement" do
    assert {:ok, [statement]} = OFX.parse(fixture("kreditkarte.ofx"))

    assert statement.bank_id == nil
    assert statement.acct_id == "4111000000001111"
    assert statement.ledger_balance == %{amount: -2_599, date: ~D[2026-10-08]}

    assert [
             %{fitid: "CC-1", date: ~D[2026-10-04], amount: -2_100, memo: "Zwei Karten"},
             %{fitid: "CC-2", date: ~D[2026-10-06], amount: -499, memo: nil}
           ] = statement.transactions
  end

  test "reads every statement of a file" do
    content =
      String.replace(
        sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1<FITID>A")),
        "</STMTTRNRS>",
        "</STMTTRNRS><STMTTRNRS><STMTRS><BANKACCTFROM><BANKID>1<ACCTID>456</BANKACCTFROM>" <>
          "</STMTRS></STMTTRNRS>"
      )

    assert {:ok, [first, second]} = OFX.parse(content)
    assert {first.acct_id, length(first.transactions)} == {"123", 1}
    assert {second.acct_id, second.transactions, second.ledger_balance} == {"456", [], nil}
  end

  test "decodes entities and leaves out end tags and blanks" do
    content =
      sgml(
        transaction(
          "<DTPOSTED>20261001<TRNAMT>-1.5<FITID> A1 </FITID><NAME>M&amp;M &lt;Shop&gt; &#228;" <>
            "</NAME><MEMO> "
        )
      )

    assert {:ok, [%{transactions: [transaction]}]} = OFX.parse(content)
    assert transaction.fitid == "A1"
    assert transaction.name == "M&M <Shop> ä"
    assert transaction.amount == -150
    assert transaction.memo == nil
  end

  test "ignores REFNUM, the time of day and the account to transfer to" do
    content =
      sgml(
        transaction(
          "<DTPOSTED>20261001235959.000[-5:EST]<TRNAMT>+12,50<FITID>A<REFNUM>99" <>
            "<BANKACCTTO><BANKID>9<ACCTID>999</BANKACCTTO>"
        )
      )

    assert {:ok, [%{acct_id: "123", transactions: [transaction]}]} = OFX.parse(content)
    assert transaction == %{fitid: "A", date: ~D[2026-10-01], amount: 1_250, name: nil, memo: nil}
  end

  test "reads a file that is not UTF-8 as Latin-1" do
    content = sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1<FITID>A<NAME>B\xE4ckerei"))

    assert {:ok, [%{transactions: [%{name: "Bäckerei"}]}]} = OFX.parse(content)
  end

  test "finds the body after a header whose capitals are longer" do
    content =
      String.duplicate("ŉ", 40) <>
        "\n" <> sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1<FITID>A"))

    assert {:ok, [%{acct_id: "123", transactions: [%{fitid: "A"}]}]} = OFX.parse(content)
  end

  test "refuses what is no OFX" do
    assert OFX.parse("Datum;Betrag\n01.10.2026;-1,00") ==
             {:error, "Die Datei ist keine OFX- oder QFX-Datei."}

    assert OFX.parse("<OFX></OFX>") == {:error, "Die Datei enthält keine Kontoumsätze."}
  end

  test "refuses a statement without account or in another currency" do
    assert OFX.parse("<OFX><STMTRS><CURDEF>EUR</STMTRS></OFX>") ==
             {:error, "Die Datei nennt kein Konto (ACCTID)."}

    assert OFX.parse(String.replace(sgml(""), "<CURDEF>EUR", "<CURDEF>USD")) ==
             {:error, "Die Datei ist in USD, Abakus kennt nur Euro."}
  end

  test "refuses a transaction it cannot read" do
    assert OFX.parse(sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1"))) ==
             {:error, "Buchung 1 hat keine FITID."}

    assert OFX.parse(sgml(transaction("<TRNAMT>-1<FITID>A"))) ==
             {:error, "Buchung 1 hat kein gültiges Datum (DTPOSTED)."}

    assert OFX.parse(sgml(transaction("<DTPOSTED>20261341<TRNAMT>-1<FITID>A"))) ==
             {:error, "Buchung 1 hat kein gültiges Datum (DTPOSTED)."}

    for amount <- ["", "abc", "-1.234", "1.000,00", String.duplicate("9", 13)] do
      assert OFX.parse(sgml(transaction("<DTPOSTED>20261001<TRNAMT>#{amount}<FITID>A"))) ==
               {:error, "Buchung 1 hat keinen gültigen Betrag (TRNAMT)."}
    end
  end

  test "takes up to 12 digits of euros" do
    content = sgml(transaction("<DTPOSTED>20261001<TRNAMT>-999999999999.99<FITID>A"))

    assert {:ok, [%{transactions: [%{amount: -99_999_999_999_999}]}]} = OFX.parse(content)
  end

  test "leaves an entity undecoded that is no character" do
    long = "&#" <> String.duplicate("9", 2_000_000) <> ";"

    content =
      sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1<FITID>A<NAME>&#x110000;<MEMO>#{long}"))

    assert {:ok, [%{transactions: [transaction]}]} = OFX.parse(content)
    assert transaction.name == "&#x110000;"
    assert transaction.memo == long
  end

  test "takes amounts with more decimals when they are whole cents" do
    content = sgml(transaction("<DTPOSTED>20261001<TRNAMT>-1.2300<FITID>A"))

    assert {:ok, [%{transactions: [%{amount: -123}]}]} = OFX.parse(content)
  end

  test "reads a file of unclosed aggregates in linear time" do
    content = sgml(String.duplicate("<STMTTRN>x", 20_000))

    {microseconds, result} = :timer.tc(fn -> OFX.parse(content) end)

    assert {:ok, [%{transactions: []}]} = result
    assert microseconds < 1_000_000
  end

  test "refuses a ledger balance it cannot read" do
    content = sgml("<LEDGERBAL><BALAMT>x<DTASOF>20261001</LEDGERBAL>")

    assert OFX.parse(content) == {:error, "Der Kontostand (LEDGERBAL) ist nicht lesbar."}
  end
end
