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

  defp sub(params) do
    Map.merge(
      %{
        "id" => "",
        "payee" => "",
        "transfer_account_id" => "",
        "category_id" => "",
        "memo" => "",
        "outflow" => "",
        "inflow" => ""
      },
      params
    )
  end

  defp split(c, params, subtransactions) do
    form(c, Map.merge(params, %{"split" => "true", "subtransactions" => subtransactions}))
  end

  defp edit(transaction),
    do: transaction.id |> Ledger.get_transaction!() |> TransactionForm.from_transaction()

  describe "to_attrs/3" do
    test "an outflow with payee, category and memo, approved", c do
      params =
        form(c, %{
          "outflow" => "1.234,5",
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

    test "the amount is inflow less outflow, a minus counts against its column", c do
      assert {:ok, %{amount: 1_200}} =
               TransactionForm.to_attrs(form(c, %{"inflow" => "12"}), c.accounts)

      assert {:ok, %{amount: 1_200}} =
               TransactionForm.to_attrs(form(c, %{"outflow" => "−12"}), c.accounts)

      assert {:ok, %{amount: 0}} = TransactionForm.to_attrs(form(c, %{}), c.accounts)
    end

    test "a tracking account takes no category", c do
      params = form(c, %{"account_id" => "#{c.depot.id}", "category_id" => "#{c.category.id}"})
      assert {:ok, %{category_id: nil}} = TransactionForm.to_attrs(params, c.accounts)
    end

    test "a transfer picked as payee between budget accounts has no category", c do
      params =
        form(c, %{
          "outflow" => "50",
          "transfer_account_id" => "#{c.savings.id}",
          "category_id" => "#{c.category.id}"
        })

      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts)

      assert %{amount: -5_000, payee_id: payee_id, category_id: nil, subtransactions: []} = attrs
      assert payee_id == c.savings.transfer_payee.id
      refute Map.has_key?(attrs, :payee_name)
    end

    test "a transfer to a tracking account has the category on the budget side", c do
      params =
        form(c, %{
          "outflow" => "50",
          "transfer_account_id" => "#{c.depot.id}",
          "category_id" => "#{c.category.id}"
        })

      assert {:ok, %{category_id: id}} = TransactionForm.to_attrs(params, c.accounts)
      assert id == c.category.id

      from_depot = %{
        params
        | "account_id" => "#{c.depot.id}",
          "transfer_account_id" => "#{c.giro.id}"
      }

      assert {:ok, %{category_id: nil, counterpart_category_id: ^id}} =
               TransactionForm.to_attrs(from_depot, c.accounts)
    end

    test "a transfer from a tracking account needs the category for the budget side", c do
      params =
        form(c, %{
          "account_id" => "#{c.depot.id}",
          "inflow" => "50",
          "transfer_account_id" => "#{c.giro.id}"
        })

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error,
                "Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}

      split =
        split(c, %{"account_id" => "#{c.depot.id}", "outflow" => "50"}, %{
          "0" => sub(%{"outflow" => "20"}),
          "1" => sub(%{"transfer_account_id" => "#{c.giro.id}", "outflow" => "30"})
        })

      assert TransactionForm.to_attrs(split, c.accounts) ==
               {:error,
                "Teil 2: Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}
    end

    test "a transfer to an account that is gone is refused", c do
      params = form(c, %{"outflow" => "50", "transfer_account_id" => "-1"})

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error, "Konto muss ausgewählt werden"}
    end

    test "a split's subtransactions have payees, transfers, categories, memos and amounts of their own",
         c do
      params =
        split(c, %{"outflow" => "100", "payee" => "Rewe"}, %{
          "0" =>
            sub(%{
              "payee" => "Bäcker",
              "category_id" => "#{c.category.id}",
              "memo" => "Brot",
              "outflow" => "80"
            }),
          "1" =>
            sub(%{
              "transfer_account_id" => "#{c.depot.id}",
              "category_id" => "#{c.category.id}",
              "outflow" => "30"
            }),
          "2" => sub(%{"transfer_account_id" => "#{c.savings.id}", "inflow" => "10"}),
          "3" => sub(%{})
        })

      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts)
      assert %{amount: -10_000, payee_name: "Rewe", category_id: nil} = attrs

      assert attrs.subtransactions == [
               %{
                 payee_name: "Bäcker",
                 category_id: c.category.id,
                 memo: "Brot",
                 amount: -8_000
               },
               %{
                 payee_id: c.depot.transfer_payee.id,
                 category_id: c.category.id,
                 memo: nil,
                 amount: -3_000
               },
               %{
                 payee_id: c.savings.transfer_payee.id,
                 category_id: nil,
                 memo: nil,
                 amount: 1_000
               }
             ]
    end

    test "unreadable amounts and dates are refused", c do
      assert TransactionForm.to_attrs(form(c, %{"outflow" => "12,345"}), c.accounts) ==
               {:error, "Betrag ist ungültig"}

      assert TransactionForm.to_attrs(form(c, %{"date" => "2026-02-30"}), c.accounts) ==
               {:error, "Datum ist ungültig"}

      params = split(c, %{}, %{"0" => sub(%{"inflow" => "x"})})

      assert TransactionForm.to_attrs(params, c.accounts) ==
               {:error, "Teil 1: Betrag ist ungültig"}

      one_subtransaction = split(c, %{}, %{"0" => sub(%{"outflow" => "5"})})

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
               "outflow" => "1.234,50",
               "inflow" => "",
               "sign" => "-",
               "payee" => "Rewe",
               "transfer_account_id" => "",
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

      assert %{"inflow" => "50,00", "sign" => "+", "payee" => "", "transfer_account_id" => giro} =
               params = edit(transfer)

      assert giro == "#{c.giro.id}"
      assert params["category_id"] == "#{c.category.id}"
    end

    test "shows a split's subtransactions with payees and memos, and saves them as they are", c do
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

      assert %{
               "payee" => "Rewe",
               "memo" => "Wocheneinkauf",
               "outflow" => "120,00",
               "inflow" => ""
             } =
               groceries

      assert %{"transfer_account_id" => id, "inflow" => "20,00"} = savings
      assert id == "#{c.savings.id}"

      original = Ledger.get_transaction!(split.id)
      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts, original)
      {:ok, _split} = Ledger.update_transaction(split, attrs)

      assert [kept, transfer] = Ledger.get_transaction!(split.id).subtransactions

      assert {kept.id, kept.payee_id, kept.memo} ==
               {String.to_integer(groceries["id"]), rewe.id, "Wocheneinkauf"}

      assert transfer.transfer_transaction_id
    end

    test "a subtransaction that is no transfer any more loses its counterpart", c do
      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -10_000,
          subtransactions: [
            %{amount: -12_000, category_id: c.category.id},
            %{amount: 2_000, payee_id: c.savings.transfer_payee.id}
          ]
        )

      params =
        split
        |> edit()
        |> TransactionForm.pick_payee("1", {:payee, ""})

      original = Ledger.get_transaction!(split.id)
      assert {:ok, attrs} = TransactionForm.to_attrs(params, c.accounts, original)
      {:ok, _split} = Ledger.update_transaction(split, attrs)

      assert [_kept, released] = Ledger.get_transaction!(split.id).subtransactions
      assert %{payee_id: nil, transfer_transaction_id: nil, amount: 2_000} = released
    end
  end

  describe "changing" do
    test "typed params go in, picked ones and the subtransactions stay the form's own", c do
      params =
        split(c, %{"category_id" => "7"}, %{"0" => sub(%{"id" => "3", "category_id" => "8"})})

      changed =
        TransactionForm.change(
          params,
          %{
            "memo" => "Neu",
            "category_id" => "",
            "subtransactions" => %{
              "0" => %{"outflow" => "5", "category_id" => "", "id" => "9"},
              "1" => %{"outflow" => "6"}
            }
          },
          c.accounts
        )

      assert %{"memo" => "Neu", "category_id" => "7"} = changed

      assert [{"0", %{"outflow" => "5", "category_id" => "8", "id" => "3"}}] =
               TransactionForm.subtransactions(changed)
    end

    test "a transfer's label keeps the transfer, anything else typed over it is a payee", c do
      params = TransactionForm.pick_payee(form(c, %{}), "main", {:transfer, c.depot.id})
      label = TransactionForm.transfer_label(c.depot)
      assert label == "↔ Depot"

      assert %{"payee" => "", "transfer_account_id" => depot} =
               TransactionForm.change(params, %{"payee" => label}, c.accounts)

      assert depot == "#{c.depot.id}"

      assert %{"payee" => "Depotbank", "transfer_account_id" => ""} =
               TransactionForm.change(params, %{"payee" => "Depotbank"}, c.accounts)
    end

    test "typing an outflow clears the inflow and back", c do
      params = form(c, %{"outflow" => "5", "inflow" => "7"})

      assert %{"outflow" => "5", "inflow" => ""} =
               TransactionForm.keep_column(params, "main", "outflow")

      assert %{"outflow" => "", "inflow" => "7"} =
               TransactionForm.keep_column(params, "main", "inflow")

      # Emptying a column leaves the other one.
      blank = %{params | "inflow" => " "}
      assert TransactionForm.keep_column(blank, "main", "inflow") == blank
    end

    test "the phone's sign moves the amounts between outflow and inflow", c do
      params =
        split(c, %{"outflow" => "100"}, %{
          "0" => sub(%{"outflow" => "80"}),
          "1" => sub(%{"inflow" => "20"})
        })

      assert TransactionForm.directed(params, "-") == "100"
      assert TransactionForm.directed(TransactionForm.side(params, "1"), "-") == "−20,00"

      toggled = TransactionForm.toggle_sign(params)
      assert %{"sign" => "+", "outflow" => "", "inflow" => "100"} = toggled
      assert %{"outflow" => "20", "inflow" => ""} = TransactionForm.side(toggled, "1")
      assert TransactionForm.remainder(toggled) == TransactionForm.remainder(params) * -1
    end

    test "income goes to Ready to Assign unless a category is chosen", c do
      rta = 99

      assert %{"category_id" => "99"} =
               TransactionForm.follow_direction(form(c, %{"inflow" => "5"}), rta)

      chosen = form(c, %{"inflow" => "5", "category_id" => "7"})
      assert %{"category_id" => "7"} = TransactionForm.follow_direction(chosen, rta)

      outflow = form(c, %{"outflow" => "5", "category_id" => "99"})
      assert %{"category_id" => ""} = TransactionForm.follow_direction(outflow, rta)
    end

    test "a payee suggests its last category; a suggestion goes when the payee changes", c do
      %Payee{last_category_id: id} = %Payee{last_category_id: c.category.id}

      assert {%{"category_id" => param}, true} =
               TransactionForm.suggest(form(c, %{}), "main", id, false)

      assert param == "#{id}"

      suggested = form(c, %{"category_id" => param})

      assert {%{"category_id" => ""}, false} =
               TransactionForm.suggest(suggested, "main", nil, true)

      assert {%{"category_id" => ^param}, false} =
               TransactionForm.suggest(suggested, "main", nil, false)

      split = split(c, %{}, %{"0" => sub(%{})})

      assert {%{"subtransactions" => %{"0" => %{"category_id" => ^param}}}, true} =
               TransactionForm.suggest(split, "0", id, false)
    end

    test "splitting gives two blank subtransactions and drops the category", c do
      params = form(c, %{"category_id" => "#{c.category.id}"}) |> TransactionForm.split()

      assert %{"split" => "true", "category_id" => ""} = params
      assert ["0", "1"] = params |> TransactionForm.subtransactions() |> Enum.map(&elem(&1, 0))
    end

    test "subtransactions are added and removed; removing one of the last two ends the split",
         c do
      params = form(c, %{}) |> TransactionForm.split() |> TransactionForm.add_subtransaction()

      assert ["0", "1", "2"] =
               params |> TransactionForm.subtransactions() |> Enum.map(&elem(&1, 0))

      params =
        params
        |> TransactionForm.remove_subtransaction("1")
        |> TransactionForm.put_side("2", %{"category_id" => "#{c.category.id}"})

      assert ["0", "2"] = params |> TransactionForm.subtransactions() |> Enum.map(&elem(&1, 0))

      assert %{"split" => "false", "subtransactions" => %{}, "category_id" => category} =
               TransactionForm.remove_subtransaction(params, "0")

      assert category == "#{c.category.id}"
    end

    test "the remainder is what the subtransactions leave, signed", c do
      params =
        split(c, %{"outflow" => "100"}, %{
          "0" => sub(%{"outflow" => "80"}),
          "1" => sub(%{"inflow" => "5"})
        })

      assert TransactionForm.remainder(params) == -2_500
      assert TransactionForm.remainder(%{params | "outflow" => "x"}) == nil
    end
  end

  describe "category fields" do
    test "show where a category goes", c do
      assert TransactionForm.category?(form(c, %{}), "main", c.accounts)

      refute TransactionForm.category?(
               form(c, %{"account_id" => "#{c.depot.id}"}),
               "main",
               c.accounts
             )

      refute TransactionForm.category?(form(c, %{"split" => "true"}), "main", c.accounts)

      transfer = form(c, %{"transfer_account_id" => "#{c.savings.id}"})
      refute TransactionForm.category?(transfer, "main", c.accounts)

      assert TransactionForm.category?(
               %{transfer | "transfer_account_id" => "#{c.depot.id}"},
               "main",
               c.accounts
             )

      params =
        split(c, %{}, %{
          "0" => sub(%{"transfer_account_id" => "#{c.depot.id}"}),
          "1" => sub(%{"transfer_account_id" => "#{c.savings.id}"}),
          "2" => sub(%{})
        })

      assert TransactionForm.category?(params, "0", c.accounts)
      refute TransactionForm.category?(params, "1", c.accounts)
      assert TransactionForm.category?(params, "2", c.accounts)

      assert {giro, depot} = TransactionForm.crossing(params, "0", c.accounts)
      assert {giro.id, depot.id} == {c.giro.id, c.depot.id}
      assert TransactionForm.crossing(params, "1", c.accounts) == nil
    end
  end
end
