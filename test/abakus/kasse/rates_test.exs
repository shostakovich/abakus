defmodule Abakus.Kasse.RatesTest do
  use Abakus.DataCase

  import Abakus.Kasse.ActivityTexts
  import Abakus.KasseFixtures
  import Abakus.UsersFixtures

  alias Abakus.ExchangeRates
  alias Abakus.ExchangeRates.ExchangeRate
  alias Abakus.Kasse.{AccessError, Expenses, Rates}
  alias Abakus.Money
  alias Abakus.Users.Scope

  @today ~D[2026-10-02]

  defp ecb!(currency, date, rate), do: ExchangeRates.store([{currency, date, Decimal.new(rate)}])

  defp rate(currency, date), do: Rates.rate(Scope.system(), currency, date, today: @today)

  setup do
    ecb!("USD", ~D[2026-09-29], "1.10")
    ecb!("USD", ~D[2026-09-30], "1.11")
    ecb!("GBP", ~D[2026-09-30], "0.85")
    :ok
  end

  test "refuse a signed-in user who is not a person" do
    outsider = Scope.for_user(user_fixture())
    attrs = %{currency: "USD", date: ~D[2026-09-30], rate: 1.2}

    assert_raise AccessError, fn -> Rates.rate(outsider, "USD", ~D[2026-09-30]) end
    assert_raise AccessError, fn -> Rates.put_manual_rate(outsider, attrs) end
    assert_raise AccessError, fn -> Rates.delete_manual_rate(outsider, "USD", ~D[2026-09-30]) end
    assert ExchangeRates.list_manual_rates() == []
  end

  describe "rate/4" do
    test "is 1 for euros" do
      assert rate(" eur ", ~D[2026-09-01]) ==
               {:ok, %{currency: "EUR", source: :fixed, date: ~D[2026-09-01], rate: 1.0}}
    end

    test "is the latest ECB rate not after the date, within ten days, as a float" do
      assert rate("usd", ~D[2026-10-02]) ==
               {:ok, %{currency: "USD", source: :ecb, date: ~D[2026-09-30], rate: 1.11}}

      assert {:ok, %{date: ~D[2026-09-29], rate: 1.1}} = rate("USD", ~D[2026-09-29])

      assert {:ok, %{date: ~D[2026-09-30]}} =
               Rates.rate(Scope.system(), "USD", ~D[2026-10-10], today: ~D[2026-10-10])

      assert Rates.rate(Scope.system(), "USD", ~D[2026-10-11], today: ~D[2026-10-11]) ==
               {:error, :no_rate}
    end

    test "counts a date after today as today" do
      assert {:ok, %{date: ~D[2026-09-30]}} =
               Rates.rate(Scope.system(), "USD", ~D[2026-12-24], today: ~D[2026-10-02])

      assert Rates.rate(Scope.system(), "USD", ~D[2026-12-24], today: ~D[2026-12-24]) ==
               {:error, :no_rate}
    end

    test "is missing for an unknown or invalid currency" do
      assert rate("CHF", ~D[2026-09-30]) == {:error, :no_rate}
      assert rate("US", ~D[2026-09-30]) == {:error, :no_rate}
      assert rate("", ~D[2026-09-30]) == {:error, :no_rate}
    end

    test "converts a stored ECB rate to the same float as its quoted text" do
      ecb!("IDR", ~D[2026-09-30], "17342.81")
      ecb!("HUF", ~D[2026-09-30], "389.650")

      assert {:ok, %{rate: 17_342.81}} = rate("IDR", ~D[2026-09-30])
      assert {:ok, %{rate: 389.65}} = rate("HUF", ~D[2026-09-30])
    end
  end

  describe "manual rates" do
    setup do
      {:ok, _rate} =
        Rates.put_manual_rate(Scope.system(), %{
          currency: " usd ",
          date: ~D[2026-09-30],
          rate: 1.2
        })

      :ok
    end

    test "apply from their date on, however old, before the ECB rates" do
      assert {:ok, %{source: :manual, rate: 1.2}} = rate("USD", ~D[2026-10-02])

      assert {:ok, %{source: :manual, rate: 1.2}} =
               Rates.rate(Scope.system(), "USD", ~D[2027-05-01], today: ~D[2027-05-01])

      assert {:ok, %{source: :ecb, rate: 1.1}} = rate("USD", ~D[2026-09-29])
    end

    test "replace a manual rate of the same day, but leave the ECB rate" do
      {:ok, _rate} =
        Rates.put_manual_rate(Scope.system(), %{currency: "USD", date: ~D[2026-09-30], rate: 1.21})

      assert [%ExchangeRate{currency: "USD", rate: rate}] = ExchangeRates.list_manual_rates()
      assert Decimal.equal?(rate, "1.21")

      assert Repo.get_by!(ExchangeRate, currency: "USD", source: :ecb, date: ~D[2026-09-30]).rate ==
               Decimal.new("1.11")
    end

    test "are logged when saved and deleted" do
      {:ok, _rate} =
        Rates.put_manual_rate(Scope.system(), %{currency: "USD", date: ~D[2026-09-30], rate: 1.21})

      {:ok, _activity} = Rates.delete_manual_rate(Scope.system(), "usd", ~D[2026-09-30])

      assert activity_texts() == [
               "Manueller Kurs für USD ab 30.09.2026 gelöscht",
               "Manueller Kurs für USD ab 30.09.2026 gespeichert: 1 € = 1,21 USD",
               "Manueller Kurs für USD ab 30.09.2026 gespeichert: 1 € = 1,2 USD"
             ]
    end

    test "leave the ECB rate of their day when deleted" do
      {:ok, _activity} = Rates.delete_manual_rate(Scope.system(), "USD", ~D[2026-09-30])

      assert {:ok, %{source: :ecb, rate: 1.11}} = rate("USD", ~D[2026-10-02])
      assert ExchangeRates.list_manual_rates() == []
    end

    test "cannot be deleted twice, or for a currency that has none" do
      {:ok, _activity} = Rates.delete_manual_rate(Scope.system(), "USD", ~D[2026-09-30])

      assert Rates.delete_manual_rate(Scope.system(), "USD", ~D[2026-09-30]) ==
               {:error, :not_found}

      assert Rates.delete_manual_rate(Scope.system(), "GBP", ~D[2026-09-30]) ==
               {:error, :not_found}
    end

    for {currency, rate, field, message} <- [
          {"EUR", 1.0, :currency, "Für Euro braucht es keinen Kurs."},
          {"US", 1.0, :currency, "Bitte einen dreistelligen Währungscode angeben (z. B. USD)."},
          {"USD", 0.0, :rate, "Der Kurs muss größer als 0 sein."},
          {"USD", -1.0, :rate, "Der Kurs muss größer als 0 sein."},
          {"USD", 1.0e10, :rate, "Der Kurs muss größer als 0 sein."},
          {"USD", nil, :rate, "Der Kurs muss größer als 0 sein."}
        ] do
      test "refuse #{currency} at #{inspect(rate)}" do
        assert {:error, changeset} =
                 Rates.put_manual_rate(Scope.system(), %{
                   currency: unquote(currency),
                   date: ~D[2026-09-30],
                   rate: unquote(rate)
                 })

        assert errors_on(changeset) == %{unquote(field) => [unquote(message)]}
      end
    end

    test "need a date" do
      assert {:error, changeset} =
               Rates.put_manual_rate(Scope.system(), %{currency: "USD", rate: 1.2})

      assert errors_on(changeset) == %{date: ["Bitte ein Datum angeben."]}
    end
  end

  test "a foreign expense saved now has the euro amount of the rate parsed from the ECB's text" do
    h = household()
    ecb!("JPY", ~D[2026-09-30], "158.37")
    form = Expenses.new_form(scope_of(h.anna), today: @today)
    form = %{form | title: "Ramen", amount: "12345", currency: "JPY", category_id: h.food}

    {:ok, expense} = Expenses.save_form(Scope.system(), form, nil, today: @today)

    assert {expense.fx_rate, expense.fx_source} == {String.to_float("158.37"), :ecb}

    assert {:ok, expense.amount_cents} ==
             Money.to_eur_cents(12_345, "JPY", String.to_float("158.37"))
  end
end
