defmodule Abakus.YnabImport.UnsupportedTest do
  use ExUnit.Case, async: true

  alias Abakus.YnabImport.Unsupported

  @need %{
    "goal_type" => "NEED",
    "goal_cadence" => 1,
    "goal_cadence_frequency" => 1,
    "goal_target" => 10_000
  }

  test "an empty plan and a plain one have no problems" do
    assert Unsupported.problems(%{}) == []
    assert Unsupported.problems(plan()) == []
  end

  test "accounts outside checking, savings and cash in the budget; tracking accounts are fine" do
    plan =
      plan(
        accounts: [
          account("Kreditkarte", "lineOfCredit", false),
          account("Haus", "otherAsset", true),
          account("Depot", "otherAsset", false),
          Map.delete(account("Ohne Angabe", "otherAsset", true), "on_budget"),
          %{account("Alt", "creditCard", true) | "deleted" => true}
        ]
      )

    assert Unsupported.problems(plan) == [
             "Account “Kreditkarte” is of type lineOfCredit.",
             "Account “Haus” is of type otherAsset."
           ]
  end

  test "targets YNAB's starter plan has: weekly ones, other types, empty amounts and missing dates" do
    plan =
      plan(
        months: [
          month("2026-10-01", [
            Map.merge(@need, %{"goal_cadence" => 2}),
            Map.merge(@need, %{"goal_cadence" => 13, "goal_target_month" => nil}),
            Map.merge(@need, %{
              "goal_cadence" => 0,
              "goal_cadence_frequency" => nil,
              "goal_target_date" => "2027-03-01"
            }),
            Map.merge(@need, %{"goal_target" => 0}),
            %{"goal_type" => "TB"}
          ])
        ]
      )

    assert Unsupported.problems(plan) == [
             "Category “🛒 Lebensmittel” has a target that repeats neither monthly nor yearly.",
             "Category “🛒 Lebensmittel” has a target by a date without a due date.",
             "Category “🛒 Lebensmittel” has a target of 0.00, which is not a positive amount in whole cents.",
             "Category “🛒 Lebensmittel” has a target of type TB."
           ]

    without_date = Map.merge(@need, %{"goal_cadence" => 0, "goal_cadence_frequency" => 0})

    assert Unsupported.problems(plan(months: [month("2026-10-01", [without_date])])) == [
             "Category “🛒 Lebensmittel” has a target by a date without a due date."
           ]
  end

  test "assignments and parts that are not whole cents" do
    plan =
      plan(
        months: [month("2026-10-01", [%{"budgeted" => 1_001}])],
        transactions: [transaction(%{"id" => "t1", "amount" => -2_000})],
        subtransactions: [part(-1_001), part(-999)]
      )

    assert Unsupported.problems(plan) == [
             "Category “🛒 Lebensmittel” has an assignment in 2026-10 that is not whole cents: 1.001.",
             "A part of transaction t1 on 2026-10-01 has an amount that is not whole cents: -1.001.",
             "A part of transaction t1 on 2026-10-01 has an amount that is not whole cents: -0.999."
           ]
  end

  test "a split with a single part left" do
    plan =
      plan(
        transactions: [transaction(%{"id" => "t1", "category_id" => "cat-split"})],
        subtransactions: [part(-1_000), %{part(-500) | "deleted" => true}]
      )

    assert Unsupported.problems(plan) == [
             "Transaction t1 on 2026-10-01 is a split with a single part."
           ]
  end

  test "references to deleted or internal records; a split's own category is ignored" do
    plan =
      plan(
        transactions: [
          transaction(%{
            "id" => "t1",
            "account_id" => "gone",
            "payee_id" => "gone",
            "category_id" => "cat-internal"
          }),
          transaction(%{"id" => "t2", "category_id" => "cat-split"})
        ],
        subtransactions: [
          %{part(-500) | "transaction_id" => "t2"},
          %{part(-500) | "transaction_id" => "t2", "category_id" => "cat-gone"}
        ]
      )

    assert Unsupported.problems(plan) == [
             "Transaction t1 on 2026-10-01 is in an account that was deleted.",
             "Transaction t1 on 2026-10-01 has a payee that was deleted.",
             "Transaction t1 on 2026-10-01 has a category that was deleted or is internal.",
             "A part of transaction t2 on 2026-10-01 has a category that was deleted or is internal."
           ]
  end

  defp plan(fields \\ []) do
    Map.merge(
      %{
        "accounts" => [account("Girokonto", "checking", true)],
        "payees" => [%{"id" => "payee", "name" => "REWE", "deleted" => false}],
        "categories" => [
          %{"id" => "cat", "name" => "🛒 Lebensmittel", "internal" => false, "deleted" => false},
          %{
            "id" => "cat-internal",
            "name" => "Deferred Income",
            "internal" => true,
            "deleted" => false
          }
        ],
        "months" => [],
        "transactions" => [],
        "subtransactions" => []
      },
      Map.new(fields, fn {key, value} -> {Atom.to_string(key), value} end)
    )
  end

  defp account(name, type, on_budget),
    do: %{
      "id" => "acc",
      "name" => name,
      "type" => type,
      "on_budget" => on_budget,
      "deleted" => false
    }

  defp month(month, categories) do
    %{
      "month" => month,
      "deleted" => false,
      "categories" =>
        Enum.map(
          categories,
          &Map.merge(%{"id" => "cat", "name" => "🛒 Lebensmittel", "budgeted" => 0}, &1)
        )
    }
  end

  defp transaction(fields) do
    Map.merge(
      %{
        "date" => "2026-10-01",
        "amount" => -1_000,
        "account_id" => "acc",
        "payee_id" => "payee",
        "deleted" => false
      },
      fields
    )
  end

  defp part(amount),
    do: %{
      "transaction_id" => "t1",
      "amount" => amount,
      "category_id" => "cat",
      "deleted" => false
    }
end
