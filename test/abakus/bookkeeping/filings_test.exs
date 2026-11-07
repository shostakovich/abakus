defmodule Abakus.Bookkeeping.FilingsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.BookkeepingFixtures
  import ExUnit.CaptureLog

  alias Abakus.{Bookkeeping, Ledger, UsersFixtures}
  alias Abakus.Bookkeeping.{FakeElster, Filing, Filings, FixedAssets, VatReturns}
  alias Abakus.Users.Scope

  setup do
    scope = budget_scope()
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    elster_fixture(scope)
    fix_now(~U[2027-04-15 10:00:00Z])
    %{scope: scope, kontist: kontist}
  end

  defp booked(c, date, amount, category, vat) do
    transaction = transaction_fixture(account_id: c.kontist.id, date: date, amount: amount)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(c.scope, Bookkeeping.get_transaction(c.scope, transaction.id), %{
        "transaction" => %{"category" => category, "vat" => vat}
      })

    transaction
  end

  defp change_vat(c, transaction, category, vat),
    do:
      Bookkeeping.save_tax_lines(c.scope, Bookkeeping.get_transaction(c.scope, transaction.id), %{
        "transaction" => %{"category" => category, "vat" => vat}
      })

  defp sent!(c) do
    FakeElster.serve()
    {:ok, filing} = Filings.send_vat_quarter(c.scope, 2027, 1, "4711")
    filing
  end

  describe "send_vat_quarter/4" do
    test "sends the quarter through ELSTER, keeps its protocol and locks the quarter", c do
      booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
      FakeElster.serve()

      assert {:ok, %Filing{} = filing} = Filings.send_vat_quarter(c.scope, 2027, 1, "4711")

      assert filing.kind == :vat_quarter
      assert {filing.first, filing.last} == {~D[2027-01-01], ~D[2027-03-31]}
      assert filing.kennzahlen == %{"81" => 1_000, "83" => 19_000}
      assert filing.transfer_ticket == "et-1"
      assert filing.sent_at == ~U[2027-04-15 10:00:00.000000Z]
      assert Filings.get(c.scope, filing.id).protocol == "%PDF-1.4 Protokoll"

      assert [sent] = FakeElster.submissions()
      assert sent.pin == "4711"
      assert sent.tax_number == "30/123/45678"
      assert sent.state_number == "11"
      assert sent.datenart_version == "UStVA_2027"
      assert sent.certificate == "PKCS12 certificate"
      assert sent.xml =~ "<Steuernummer>1130012345678</Steuernummer>"
      assert sent.xml =~ "<Kz81>1000</Kz81>"
      assert sent.xml =~ "<Testmerker>700000004</Testmerker>"

      assert Filings.locked?(c.scope, ~D[2027-01-01])
      assert Filings.locked?(c.scope, ~D[2027-03-31])
      refute Filings.locked?(c.scope, ~D[2027-04-01])
      refute Filings.locked?(Scope.for_user(UsersFixtures.user_fixture()), ~D[2027-02-10])
    end

    test "a failed send locks nothing", c do
      FakeElster.serve(error: "ERiC-Fehler 610301200: Die Daten sind fehlerhaft.")

      log =
        capture_log(fn ->
          assert Filings.send_vat_quarter(c.scope, 2027, 1, "4711") ==
                   {:error, "ERiC-Fehler 610301200: Die Daten sind fehlerhaft."}
        end)

      assert log =~ "610301200"
      refute log =~ "4711"

      assert Filings.vat_quarter(c.scope, 2027, 1) == nil
      refute Filings.locked?(c.scope, ~D[2027-02-10])
    end

    test "sends a quarter once, and only once it is over", c do
      sent!(c)

      assert Filings.send_vat_quarter(c.scope, 2027, 1, "4711") ==
               {:error, "Zeitraum ist festgeschrieben"}

      assert Filings.send_vat_quarter(c.scope, 2027, 2, "4711") ==
               {:error, "Das Quartal ist noch nicht vorbei."}

      assert length(FakeElster.submissions()) == 1
    end

    test "sends nothing without what ELSTER needs or without a PIN", c do
      FakeElster.serve()
      {:ok, _settings} = Filings.remove_certificate(c.scope)

      assert Filings.send_vat_quarter(c.scope, 2027, 1, "4711") ==
               {:error, "Es fehlt: ELSTER-Zertifikat."}

      elster_fixture(c.scope)

      assert Filings.send_vat_quarter(c.scope, 2027, 1, " ") ==
               {:error, "Bitte die PIN des Zertifikats eingeben."}

      config = Application.fetch_env!(:abakus, Abakus.Bookkeeping.Elster)
      Application.put_env(:abakus, Abakus.Bookkeeping.Elster, Keyword.delete(config, :vendor_id))
      on_exit(fn -> Application.put_env(:abakus, Abakus.Bookkeeping.Elster, config) end)

      assert Filings.missing(c.scope) == ["ELSTER auf dem Server"]
      assert FakeElster.submissions() == []
    end
  end

  test "names what sending lacks in the settings", c do
    other = Scope.for_user(UsersFixtures.user_fixture())

    assert Filings.missing(other) ==
             ["Name", "Straße", "PLZ", "Ort", "Steuernummer", "Bundesland", "ELSTER-Zertifikat"]

    assert Filings.missing(c.scope) == []
  end

  describe "a sent quarter" do
    test "refuses to change a tax line dated in it, but keeps one saved unchanged", c do
      licence = booked(c, ~D[2027-02-10], -11_900, "office_supplies", "19")
      later = booked(c, ~D[2027-04-02], -11_900, "office_supplies", "19")
      sent!(c)

      assert change_vat(c, licence, "office_supplies", "7") == {:error, :locked}
      assert change_vat(c, licence, "", "") == {:error, :locked}
      assert {:ok, _lines} = change_vat(c, licence, "office_supplies", "19")
      assert {:ok, _lines} = change_vat(c, later, "office_supplies", "7")

      lines = Bookkeeping.tax_lines(c.scope, [Bookkeeping.get_transaction(c.scope, licence.id)])
      assert lines[{licence.id, nil}].vat == :rate_19
    end

    test "takes its transactions out of the inbox", c do
      locked = transaction_fixture(account_id: c.kontist.id, date: ~D[2027-03-31], amount: -500)
      open = transaction_fixture(account_id: c.kontist.id, date: ~D[2027-04-01], amount: -500)
      sent!(c)

      ids = for {transaction, _missing} <- Bookkeeping.inbox(c.scope), do: transaction.id

      assert open.id in ids
      refute locked.id in ids
    end

    test "keeps a disposal dated in it as it is", c do
      asset = fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01"})
      disposed = disposal_fixture(c.scope, asset, %{"date" => "2027-01-20"})
      later = fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01"})
      sent!(c)

      assert {:error, changeset} =
               FixedAssets.record_disposal(c.scope, disposed, %{"amount" => "300"})

      assert errors_on(changeset).date == ["Zeitraum ist festgeschrieben"]

      assert {:error, changeset} =
               FixedAssets.record_disposal(c.scope, later, %{
                 "kind" => "withdrawal",
                 "date" => "2027-03-01",
                 "amount" => "100",
                 "vat" => "19"
               })

      assert errors_on(changeset).date == ["Zeitraum ist festgeschrieben"]
      assert FixedAssets.remove_disposal(c.scope, disposed) == {:error, :locked}
      assert FixedAssets.delete(c.scope, disposed) == {:error, :locked}

      assert {:ok, _asset} =
               FixedAssets.record_disposal(c.scope, later, %{
                 "kind" => "withdrawal",
                 "date" => "2027-04-01",
                 "amount" => "100",
                 "vat" => "19"
               })

      assert {:ok, _asset} = FixedAssets.record_disposal(c.scope, disposed, %{"amount" => "238"})
    end
  end

  test "tells whether the Kennzahlen still match those sent", c do
    transaction = booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
    filing = sent!(c)

    assert Filings.matches?(filing, VatReturns.quarter(c.scope, 2027, 1))

    {:ok, _changed} = Ledger.update_transaction(c.scope, transaction, %{amount: 238_000})

    refute Filings.matches?(filing, VatReturns.quarter(c.scope, 2027, 1))
  end
end
