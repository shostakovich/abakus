defmodule AbakusWeb.RegisterWindowTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Ecto.Query, only: [from: 2]

  alias Abakus.{Ledger, Money, Repo}
  alias Abakus.Ledger.Transaction

  setup :register_and_log_in_user

  setup do
    %{giro: account_fixture(name: "Girokonto", kind: :checking)}
  end

  test "opens with the newest 100 and loads 100 more near the end", c do
    ids = transactions(c.giro, 250)
    {:ok, view, html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    assert html =~ ~s(id="tx-#{Enum.at(ids, 99)}")
    assert shown?(view, Enum.at(ids, 99))
    refute shown?(view, Enum.at(ids, 100))

    load_more(view)
    assert shown?(view, Enum.at(ids, 199))
    refute shown?(view, Enum.at(ids, 200))

    load_more(view)
    assert shown?(view, Enum.at(ids, 249))
    refute has_element?(view, "#register-more")

    render_hook(view, "load_more", %{})
    assert shown?(view, Enum.at(ids, 249))
  end

  test "exactly 100 leave nothing to load", c do
    transactions(c.giro, 100)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    refute has_element?(view, "#register-more")
  end

  test "toggling the running balance keeps the loaded rows and the open editor", c do
    ids = transactions(c.giro, 150)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
    load_more(view)

    view |> element("#tx-#{List.last(ids)} td.app-payee") |> render_click()
    view |> element("#tx-#{List.last(ids)} td.app-payee") |> render_click()
    assert has_element?(view, "#tx-editor")

    view |> element("#running-toggle") |> render_click()
    assert has_element?(view, "#tx-editor")
    assert shown?(view, Enum.at(ids, 148))
  end

  test "the running balance counts on across loaded pages", c do
    ids = transactions(c.giro, 250)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?running=1")

    load_more(view)

    # Each transaction is -1,00 € times its place, so the balance after the 150th leaves out the 149 newer ones.
    balance = -100 * (Enum.sum(1..250) - Enum.sum(1..149))
    assert has_element?(view, "#tx-#{Enum.at(ids, 149)} .app-run", Money.amount(balance))
  end

  test "the running balance shows beside a match proposal", c do
    [newest | _older] = transactions(c.giro, 3)

    {:ok, proposal} =
      Ledger.create_transaction(budget_scope(), %{
        account_id: c.giro.id,
        date: ~D[2026-10-14],
        amount: -100,
        source: :bank,
        matched_transaction_id: newest
      })

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?running=1")

    assert has_element?(view, "#proposal-#{proposal.id}")
    assert has_element?(view, "#tx-#{newest} .app-run", Money.amount(-600))
  end

  test "a view with more than 100 shows its newest 100 first", c do
    ids =
      transactions(c.giro, 300, &%{cleared: if(rem(&1, 2) == 0, do: :uncleared, else: :cleared)})

    uncleared = ids |> Enum.drop(1) |> Enum.take_every(2)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?filter=uncleared")

    assert shown?(view, Enum.at(uncleared, 99))
    refute shown?(view, Enum.at(uncleared, 100))

    load_more(view)
    assert shown?(view, List.last(uncleared))
    refute shown?(view, Enum.at(ids, -2))
    refute has_element?(view, "#register-more")
  end

  test "selecting all takes transactions not loaded yet", c do
    transactions(c.giro, 250, fn _index -> %{approved: false} end)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    view |> element("#select-all") |> render_click()
    assert has_element?(view, "#bulk", "250 Buchungen")
    assert has_element?(view, "#select-all[checked]")

    view |> element("#approve-selected") |> render_click()
    assert has_element?(view, "#flash-info", "250 bestätigt")

    refute Repo.exists?(
             from t in Transaction, where: t.account_id == ^c.giro.id and not t.approved
           )
  end

  test "unchecking one after selecting all keeps the others", c do
    ids = transactions(c.giro, 150)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    view |> element("#select-all") |> render_click()
    view |> element("#tx-#{hd(ids)}-select") |> render_click()
    assert has_element?(view, "#bulk", "149 Buchungen")
    refute has_element?(view, "#select-all[checked]")
  end

  test "the selection of transactions not loaded yet stays after a change", c do
    groceries = category_fixture(name: "Lebensmittel")
    transactions(c.giro, 150)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    view |> element("#select-all") |> render_click()
    view |> form("#categorise-form") |> render_submit(%{category_id: groceries.id})

    assert has_element?(view, "#flash-info", "150 kategorisiert")
    assert has_element?(view, "#bulk", "150 Buchungen")

    assert Repo.aggregate(from(t in Transaction, where: t.category_id == ^groceries.id), :count) ==
             150
  end

  test "selecting all again clears the selection", c do
    transactions(c.giro, 150)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    view |> element("#select-all") |> render_click()
    view |> element("#select-all") |> render_click()
    refute has_element?(view, "#bulk-status", "Buchung")
  end

  test "a search finds transactions not loaded yet", c do
    stadtwerke = payee_fixture(name: "Stadtwerke")
    ids = transactions(c.giro, 300, &if(&1 == 300, do: %{payee_id: stadtwerke.id}, else: %{}))
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
    refute shown?(view, List.last(ids))

    view |> form("#register-search", q: "stadtwerke") |> render_change()
    assert shown?(view, List.last(ids))
    refute shown?(view, hd(ids))
  end

  test "a search with more than 100 hits loads more", c do
    stadtwerke = payee_fixture(name: "Stadtwerke")
    ids = transactions(c.giro, 250, &if(&1 > 100, do: %{payee_id: stadtwerke.id}, else: %{}))
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?q=stadtwerke")

    assert shown?(view, Enum.at(ids, 199))
    refute shown?(view, Enum.at(ids, 200))

    load_more(view)
    assert shown?(view, List.last(ids))
    refute has_element?(view, "#register-more")
  end

  # `count` transactions in the account, newest first: the one at place n is dated n days back and is -n,00 €.
  defp transactions(account, count, attrs \\ fn _place -> %{} end) do
    now = DateTime.utc_now()

    rows =
      for place <- 1..count do
        Map.merge(
          %{
            user_id: budget_scope().user.id,
            account_id: account.id,
            date: Date.add(~D[2026-10-15], -place),
            amount: -100 * place,
            cleared: :uncleared,
            approved: true,
            source: :manual,
            payee_id: nil,
            inserted_at: now,
            updated_at: now
          },
          attrs.(place)
        )
      end

    Repo.insert_all(Transaction, rows)

    Repo.all(
      from t in Transaction,
        where: t.account_id == ^account.id,
        order_by: [desc: t.date, desc: t.id],
        select: t.id
    )
  end

  defp shown?(view, id),
    do: has_element?(view, "#tx-#{id}") and has_element?(view, "#tx-card-#{id}")

  defp load_more(view), do: view |> element("#register-more") |> render_hook("load_more", %{})
end
