defmodule AbakusWeb.TransactionFormTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.Payee
  alias AbakusWeb.TransactionForm

  setup do
    giro = account_fixture(name: "Girokonto")
    savings = account_fixture(name: "Sparkonto", kind: :savings)
    depot = account_fixture(name: "Depot", kind: :tracking)
    accounts = Map.new([giro, savings, depot], &{&1.id, &1})

    %{
      giro: giro,
      savings: savings,
      depot: depot,
      accounts: accounts,
      category: category_fixture()
    }
  end

  defp form(c, params), do: Map.merge(TransactionForm.new(c.giro.id, ~D[2026-10-09]), params)

  defp subtransaction(target, amount, extra \\ %{}),
    do:
      Map.merge(%{"id" => "", "target" => target, "amount" => amount, "category_id" => ""}, extra)

  defp edit(transaction),
    do: transaction.id |> Ledger.get_transaction!() |> TransactionForm.from_transaction()

  describe "to_attrs/3" do
    test "an outflow with payee, category and memo, approved", c do
      params =
        form(c, %{
          "amount" => "1.234,5",
          "payee" => "Rewe",
          "category_id" => "#{c.category.id}",
          "memo" => " Einkauf "
        })

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:ok,
                %{
                  account_id: c.giro.id,
                  date: ~D[2026-10-09],
                  amount: -123_450,
                  memo: "Einkauf",
                  approved: true,
                  payee_name: "Rewe",
                  category_id: c.category.id,
                  subtransactions: []
                }}
    end

    test "an inflow is positive, whatever sign is typed", c do
      params = form(c, %{"amount" => "-12", "sign" => "+", "kind" => "inflow"})
      assert {:ok, %{amount: 1_200}} = TransactionForm.to_attrs(params, c.accounts)
    end

    test "a tracking account takes no category", c do
      params = form(c, %{"account_id" => "#{c.depot.id}", "category_id" => "#{c.category.id}"})
      assert {:ok, %{category_id: nil}} = TransactionForm.to_attrs(params, c.accounts)
    end

    test "a transfer between budget accounts has no category", c do
      params =
        form(c, %{
          "kind" => "transfer",
          "amount" => "50",
          "other_account_id" => "#{c.savings.id}",
          "category_id" => "#{c.category.id}",
          "payee" => "Rewe"
        })

      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts)

      assert %{amount: -5_000, payee_id: payee_id, category_id: nil, subtransactions: []} = attrs
      assert payee_id == c.savings.transfer_payee.id
      refute Map.has_key?(attrs, :payee_name)
    end

    test "a transfer to a tracking account has the category on the budget side", c do
      params =
        form(c, %{
          "kind" => "transfer",
          "amount" => "50",
          "other_account_id" => "#{c.depot.id}",
          "category_id" => "#{c.category.id}"
        })

      assert {:ok, %{category_id: id}} = TransactionForm.to_attrs(params, c.accounts)
      assert id == c.category.id

      from_depot = %{
        params
        | "account_id" => "#{c.depot.id}",
          "other_account_id" => "#{c.giro.id}"
      }

      assert {:ok, %{category_id: nil, counterpart_category_id: ^id}} =
               TransactionForm.to_attrs(from_depot, c.accounts)
    end

    test "a transfer from a tracking account needs the category for the budget side", c do
      params =
        form(c, %{
          "account_id" => "#{c.depot.id}",
          "kind" => "transfer",
          "amount" => "50",
          "other_account_id" => "#{c.giro.id}"
        })

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error,
                "Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}

      split =
        form(c, %{
          "account_id" => "#{c.depot.id}",
          "amount" => "50",
          "split" => "true",
          "subtransactions" => %{
            "0" => subtransaction("", "20"),
            "1" => subtransaction("a:#{c.giro.id}", "30")
          }
        })

      assert TransactionForm.to_attrs(split, c.accounts) ==
               {:error,
                "Teil 2: Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}
    end

    test "a transfer needs the other account", c do
      params = form(c, %{"kind" => "transfer", "amount" => "50"})

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error, "Gegenkonto muss ausgewählt werden"}
    end

    test "a split's subtransactions count in its direction and pick a category or an account",
         c do
      params =
        form(c, %{
          "amount" => "100",
          "payee" => "Rewe",
          "split" => "true",
          "subtransactions" => %{
            "0" => subtransaction("c:#{c.category.id}", "80"),
            "1" =>
              subtransaction("a:#{c.depot.id}", "30", %{"category_id" => "#{c.category.id}"}),
            "2" => subtransaction("", "−10"),
            "3" => subtransaction("", " ")
          }
        })

      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts)
      assert %{amount: -10_000, payee_name: "Rewe", category_id: nil} = attrs

      assert attrs.subtransactions == [
               %{category_id: c.category.id, amount: -8_000},
               %{
                 payee_id: c.depot.transfer_payee.id,
                 category_id: c.category.id,
                 amount: -3_000
               },
               %{category_id: nil, amount: 1_000}
             ]
    end

    test "unreadable amounts and dates are refused", c do
      assert TransactionForm.to_attrs(form(c, %{"amount" => "12,345"}), c.accounts) ==
               {:error, "Betrag ist ungültig"}

      assert TransactionForm.to_attrs(form(c, %{"date" => "2026-02-30"}), c.accounts) ==
               {:error, "Datum ist ungültig"}

      params =
        form(c, %{"split" => "true", "subtransactions" => %{"0" => subtransaction("", "x")}})

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error, "Teil 1: Betrag ist ungültig"}

      one_subtransaction =
        form(c, %{"split" => "true", "subtransactions" => %{"0" => subtransaction("", "5")}})

      assert TransactionForm.to_attrs(one_subtransaction, c.accounts) ==
               {:error, "Eine Aufteilung braucht mindestens zwei Teile"}

      assert TransactionForm.to_attrs(form(c, %{"account_id" => "-1"}), c.accounts) ==
               {:error, "Konto muss ausgewählt werden"}
    end
  end

  describe "editing" do
    test "shows an outflow as entered", c do
      transaction =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -123_450,
          payee_id: payee_fixture(name: "Rewe").id,
          category_id: c.category.id,
          memo: "Einkauf"
        )

      assert %{
               "account_id" => giro,
               "date" => "2026-10-09",
               "amount" => "1.234,50",
               "sign" => "-",
               "kind" => "outflow",
               "payee" => "Rewe",
               "category_id" => category,
               "split" => "false",
               "memo" => "Einkauf"
             } = edit(transaction)

      assert {giro, category} == {"#{c.giro.id}", "#{c.category.id}"}
    end

    test "shows a transfer from a tracking account with its counterpart's category", c do
      {:ok, transfer} =
        Ledger.create_transaction(%{
          account_id: c.depot.id,
          date: ~D[2026-10-09],
          amount: 5_000,
          payee_id: c.giro.transfer_payee.id,
          counterpart_category_id: c.category.id
        })

      assert %{"kind" => "transfer", "sign" => "+", "payee" => "", "other_account_id" => giro} =
               params = edit(transfer)

      assert giro == "#{c.giro.id}"
      assert params["category_id"] == "#{c.category.id}"
    end

    test "keeps the payees and memos of a split's subtransactions and releases a transfer subtransaction",
         c do
      rewe = payee_fixture(name: "Rewe")

      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -10_000,
          subtransactions: [
            %{
              amount: -12_000,
              payee_id: rewe.id,
              memo: "Wocheneinkauf",
              category_id: c.category.id
            },
            %{amount: 2_000, payee_id: c.savings.transfer_payee.id}
          ]
        )

      params = edit(split)
      assert [{"0", groceries}, {"1", savings}] = TransactionForm.subtransactions(params)
      assert %{"target" => "c:" <> _, "amount" => "120,00"} = groceries
      assert savings["target"] == "a:#{c.savings.id}"
      assert savings["amount"] == "−20,00"

      params = put_in(params, ["subtransactions", "1", "target"], "")
      original = Ledger.get_transaction!(split.id)

      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts, original)
      {:ok, _split} = Ledger.update_transaction(split, attrs)

      assert [kept, released] = Ledger.get_transaction!(split.id).subtransactions
      assert %{payee_id: payee_id, memo: "Wocheneinkauf", amount: -12_000} = kept
      assert payee_id == rewe.id
      assert %{payee_id: nil, transfer_transaction_id: nil, amount: 2_000} = released
    end
  end

  describe "changing" do
    test "an outflow or inflow follows its kind, a transfer keeps its direction", c do
      assert %{"sign" => "+"} = TransactionForm.change(form(c, %{}), %{"kind" => "inflow"})

      transfer = form(c, %{"kind" => "transfer", "sign" => "+"})
      assert %{"sign" => "+", "kind" => "transfer"} = TransactionForm.change(transfer, %{})
      assert %{"sign" => "-", "kind" => "transfer"} = TransactionForm.toggle_sign(transfer)
      assert %{"sign" => "+", "kind" => "inflow"} = TransactionForm.toggle_sign(form(c, %{}))
    end

    test "changed subtransactions replace the subtransactions", c do
      params =
        TransactionForm.change(form(c, %{}), %{
          "subtransactions" => %{"0" => subtransaction("", "5")}
        })

      assert [{"0", %{"amount" => "5"}}] = TransactionForm.subtransactions(params)
    end

    test "income goes to Ready to Assign unless a category is chosen", c do
      rta = 99
      inflow = form(c, %{"kind" => "inflow"})

      assert %{"category_id" => "99"} = TransactionForm.kind_changed(inflow, rta)
      chosen = %{inflow | "category_id" => "7"}
      assert %{"category_id" => "7"} = TransactionForm.kind_changed(chosen, rta)

      outflow = form(c, %{"category_id" => "99"})
      assert %{"category_id" => ""} = TransactionForm.kind_changed(outflow, rta)
    end

    test "a payee suggests its last category; a suggestion goes when the payee changes", c do
      known = %Payee{last_category_id: c.category.id}

      assert {%{"category_id" => id}, true} = TransactionForm.suggest(form(c, %{}), known, false)
      assert id == "#{c.category.id}"

      suggested = form(c, %{"category_id" => id})
      assert {%{"category_id" => ""}, false} = TransactionForm.suggest(suggested, nil, true)
      assert {%{"category_id" => ^id}, false} = TransactionForm.suggest(suggested, nil, false)
    end

    test "subtransactions are added and removed, at least two stay", c do
      params = TransactionForm.add_subtransaction(form(c, %{}))

      assert ["0", "1", "2"] =
               params |> TransactionForm.subtransactions() |> Enum.map(&elem(&1, 0))

      params =
        params
        |> TransactionForm.remove_subtransaction("1")
        |> TransactionForm.remove_subtransaction("0")

      assert ["0", "2"] = params |> TransactionForm.subtransactions() |> Enum.map(&elem(&1, 0))
    end

    test "the remainder is what the subtransactions leave", c do
      params =
        form(c, %{
          "amount" => "100",
          "subtransactions" => %{"0" => subtransaction("", "80"), "1" => subtransaction("", "−5")}
        })

      assert TransactionForm.remainder(params) == 2_500
      assert TransactionForm.remainder(%{params | "amount" => "x"}) == nil
    end
  end

  describe "category fields" do
    test "show where a category goes", c do
      assert TransactionForm.category?(form(c, %{}), c.accounts)
      refute TransactionForm.category?(form(c, %{"account_id" => "#{c.depot.id}"}), c.accounts)
      refute TransactionForm.category?(form(c, %{"split" => "true"}), c.accounts)

      transfer = form(c, %{"kind" => "transfer", "other_account_id" => "#{c.savings.id}"})
      refute TransactionForm.category?(transfer, c.accounts)

      assert TransactionForm.category?(
               %{transfer | "other_account_id" => "#{c.depot.id}"},
               c.accounts
             )

      params = form(c, %{})

      assert TransactionForm.subtransaction_category?(
               subtransaction("a:#{c.depot.id}", ""),
               params,
               c.accounts
             )

      refute TransactionForm.subtransaction_category?(
               subtransaction("a:#{c.savings.id}", ""),
               params,
               c.accounts
             )

      refute TransactionForm.subtransaction_category?(
               subtransaction("c:#{c.category.id}", ""),
               params,
               c.accounts
             )
    end
  end
end
