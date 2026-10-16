defmodule AbakusWeb.Kasse.RatesLiveTest do
  use AbakusWeb.ConnCase

  @moduletag :capture_log

  import Phoenix.LiveViewTest
  import Setzkasten.Test.Confirm
  import Abakus.Kasse.ActivityTexts
  import Abakus.KasseFixtures
  import AbakusWeb.PageText

  alias Abakus.{ExchangeRates, FakeExchangeRateSource, LocalTime}
  alias Abakus.ExchangeRates.ExchangeRate
  alias Abakus.Kasse.Rates

  setup %{conn: conn} do
    h = household()
    %{h: h, conn: log_in_participant(conn, h.anna)}
  end

  defp save(view, params),
    do: view |> form("#rate-form", rate: params) |> render_submit()

  test "no ECB and no manual rates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    assert page_title(view) == "Wechselkurse · Abakus"
    assert texts(view, "main") |> hd() =~ "Noch keine manuellen Kurse."

    assert texts(view, "#rates-stats") == [
             "Noch keine EZB-Kurse gespeichert. Neue Kurse werden täglich um 17 Uhr automatisch abgerufen."
           ]

    assert has_element?(view, "#rate_date[value='#{Date.to_iso8601(LocalTime.today())}']")
    refute has_element?(view, "#ecb-rates")
    refute has_element?(view, "#used-rates")
  end

  test "keeps the manual rate as typed through a re-render", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    view
    |> form("#rate-form", rate: %{currency: "THB", date: "2026-09-01", rate: "38,5"})
    |> render_change()

    view |> element("#rates-refresh") |> render_click()

    assert has_element?(view, "#rate_currency[value='THB']")
    assert has_element?(view, "#rate_date[value='2026-09-01']")
    assert has_element?(view, "#rate_rate[value='38,5']")
  end

  test "adds a manual rate as typed and deletes it after asking", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    save(view, %{currency: " usd ", date: "2026-10-01", rate: "1,0850"})

    assert flash(view, :info) == "Kurs für USD gespeichert."
    assert texts(view, "#manual-rates tr") == ["USD 01.10.2026 1,085 USD"]
    assert has_element?(view, "#rate_currency[value=''][phx-patch-focused]")
    assert has_element?(view, "#rate_rate[value=''][phx-patch-focused]")
    assert last_activity() == "Manueller Kurs für USD ab 01.10.2026 gespeichert: 1 € = 1,085 USD"

    confirm_click(
      view,
      "#manual-USD-2026-10-01-delete",
      "Manuellen Kurs für USD ab 01.10.2026 löschen?"
    )

    assert flash(view, :info) == "Manueller Kurs für USD gelöscht."
    refute has_element?(view, "#manual-rates")
    assert ExchangeRates.list_manual_rates() == []
  end

  test "keeps the typed values with the errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    save(view, %{currency: "EUR", date: "", rate: "abc"})

    assert texts(view, "#rate_currency-error-0") == ["Für Euro braucht es keinen Kurs."]
    assert texts(view, "#rate_date-error-0") == ["Bitte ein Datum angeben."]

    assert texts(view, "#rate_rate-error-0") == [
             "Ungültiger Wechselkurs „abc“ – bitte eine Zahl größer als 0 angeben (Einheiten der Währung pro 1 €)."
           ]

    assert has_element?(view, "#rate_rate[value=abc]")

    save(view, %{currency: "US", date: "2026-10-01", rate: ""})

    assert texts(view, "#rate_currency-error-0") ==
             ["Bitte einen dreistelligen Währungscode angeben (z. B. USD)."]

    assert texts(view, "#rate_rate-error-0") == ["Der Kurs muss größer als 0 sein."]
    assert ExchangeRates.list_manual_rates() == []
  end

  test "a rate deleted meanwhile", %{conn: conn, h: h} do
    {:ok, _rate} =
      Rates.put_manual_rate(h.ben, %{currency: "CHF", date: ~D[2026-09-01], rate: 0.95})

    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")
    {:ok, _activity} = Rates.delete_manual_rate(h.ben, "CHF", ~D[2026-09-01])

    confirm_click(view, "#manual-CHF-2026-09-01-delete")

    assert flash(view, :error) == "Diesen manuellen Kurs gibt es nicht (mehr)."
    refute has_element?(view, "#manual-rates")
  end

  test "the ECB rates, their newest day and the rates of recent expenses", %{conn: conn, h: h} do
    ExchangeRates.store([
      {"USD", ~D[2026-09-30], Decimal.new("1.0912")},
      {"USD", ~D[2026-10-01], Decimal.new("1.1195")},
      {"JPY", ~D[2026-10-01], Decimal.new("177.39")}
    ])

    usd = foreign(h, "Diner", 4200, "USD", 1.1195, "2026-10-01", h.anna, [h.anna, h.ben])
    expense = create!(usd)

    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    assert texts(view, "#rates-stats") |> hd() =~
             "Gespeichert: 3 Kurse für 2 Währungen vom 30.09.2026 bis 01.10.2026."

    assert texts(view, "#ecb-rates tr") ==
             ["JPY 01.10.2026 177,39 JPY", "USD 01.10.2026 1,1195 USD"]

    assert texts(view, "#used-rates tr") ==
             ["Diner 01.10.2026 · EZB 01.10.2026 1,1195 USD EZB"]

    assert has_element?(view, ~s(#used-rates a[href="/kasse/expenses/#{expense.id}"]))
  end

  test "loading the ECB rates in the background reports a failure", %{conn: conn} do
    FakeExchangeRateSource.stub(fn _from -> {:error, :timeout} end)
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    view |> element("#rates-refresh") |> render_click()
    render_async(view)

    assert flash(view, :error) == "Die EZB ist nicht erreichbar."
    refute has_element?(view, "#rates-refresh[aria-busy]")
    assert Abakus.Repo.aggregate(ExchangeRate, :count) == 0
  end

  test "loading runs the shared load of the ECB rates", %{conn: conn} do
    test = self()

    FakeExchangeRateSource.stub(fn _from ->
      send(test, {:loading, self()})

      receive do
        :go -> :ok
      end

      {:ok,
       [
         {"USD", ~D[2026-10-01], Decimal.new("1.1195")},
         {"JPY", ~D[2026-10-01], Decimal.new("177.39")}
       ]}
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/kasse/rates")

    view |> element("#rates-refresh") |> render_click()
    assert_receive {:loading, loader}
    assert has_element?(view, "#rates-refresh[aria-busy]")
    send(loader, :go)
    render_async(view)

    assert_received {:rates, ~D[1999-01-04]}
    assert flash(view, :info) == "EZB-Kurse aktualisiert (Stand 01.10.2026)."

    assert texts(view, "#ecb-rates tr") == [
             "JPY 01.10.2026 177,39 JPY",
             "USD 01.10.2026 1,1195 USD"
           ]

    assert %{error: nil} = ExchangeRates.last_run()
  end
end
