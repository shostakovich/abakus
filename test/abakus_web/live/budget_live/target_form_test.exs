defmodule AbakusWeb.BudgetLive.TargetFormTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.BudgetLive.TargetForm

  @oct ~D[2026-10-01]

  describe "params/2" do
    test "a new target starts monthly, setting aside" do
      assert TargetForm.params(nil, @oct) == %{
               "amount" => "",
               "cadence" => "monthly",
               "due_on" => "",
               "repeats_yearly" => "false",
               "set_aside" => "true"
             }
    end

    test "a target's fields as typed" do
      target = %{
        cadence: :by_date,
        amount: 120_000,
        due_on: ~D[2027-06-01],
        repeats_yearly: true,
        set_aside: false
      }

      assert TargetForm.params(target, @oct) == %{
               "amount" => "1.200,00",
               "cadence" => "by_date",
               "due_on" => "2027-06-01",
               "repeats_yearly" => "true",
               "set_aside" => "false"
             }
    end

    test "a repeating target's date moves on to its next due date" do
      target = %{
        cadence: :by_date,
        amount: 30_000,
        due_on: ~D[2025-09-20],
        repeats_yearly: true,
        set_aside: true
      }

      assert %{"due_on" => "2026-09-20"} = TargetForm.params(target, ~D[2026-09-01])
      assert %{"due_on" => "2027-09-20"} = TargetForm.params(target, @oct)

      assert %{"due_on" => "2025-09-20"} =
               TargetForm.params(%{target | repeats_yearly: false}, @oct)
    end
  end

  describe "attrs/2" do
    test "a monthly target drops the date and the repeat" do
      params = %{
        "amount" => "50",
        "cadence" => "monthly",
        "due_on" => "2027-06-01",
        "repeats_yearly" => "true",
        "set_aside" => "false"
      }

      assert TargetForm.attrs(params, @oct) ==
               {:ok,
                %{
                  from_month: @oct,
                  cadence: "monthly",
                  amount: 5_000,
                  due_on: nil,
                  repeats_yearly: false,
                  set_aside: false
                }}
    end

    test "a target by a date keeps its date and repeat" do
      params = %{
        "amount" => "1.200",
        "cadence" => "by_date",
        "due_on" => "2027-06-01",
        "repeats_yearly" => "true",
        "set_aside" => "true"
      }

      assert {:ok, %{amount: 120_000, due_on: "2027-06-01", repeats_yearly: true}} =
               TargetForm.attrs(params, @oct)
    end

    test "an amount that is no number is an error on the amount" do
      for amount <- ["", "zwölf"] do
        assert {:error, [amount: {message, []}]} =
                 TargetForm.attrs(%{TargetForm.params(nil, @oct) | "amount" => amount}, @oct)

        assert message =~ "Betrag"
      end
    end
  end
end
