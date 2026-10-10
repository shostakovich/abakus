defmodule AbakusWeb.RegisterReconcileTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Ecto.Query, only: [from: 2]

  alias Abakus.{Categories, Ledger, Repo}
  alias Abakus.Ledger.Transaction

  setup :register_and_log_in_user

  setup do
    %{giro: account_fixture(name: "💶 Girokonto", kind: :checking)}
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id) |> Repo.preload(:payee)

  defp cleared(account, date, amount),
    do: transaction_fixture(account_id: account.id, date: date, amount: amount, cleared: :cleared)

  defp open(conn, account) do
    {:ok, view, _html} =
      conn |> put_connect_params(%{"today" => "2026-10-10"}) |> live(~p"/accounts/#{account}")

    view |> element("#reconcile-open") |> render_click()
    view
  end

  defp enter(view, balance) do
    view |> element("#reconcile-no") |> render_click()
    view |> form("#reconcile-form", %{balance: balance}) |> render_submit()
  end

  test "a file balance counts up to its date", c do
    first = cleared(c.giro, ~D[2026-10-01], 20_000)
    second = cleared(c.giro, ~D[2026-10-08], -6_752)
    by_hand = cleared(c.giro, ~D[2026-10-09], -1_000)

    {:ok, _} =
      Ledger.put_bank_balance(c.giro, %{amount: 13_248, date: ~D[2026-10-08], source: :file})

    view = open(c.conn, c.giro)

    assert has_element?(view, "#reconcile-bank", "08.10.2026")
    assert has_element?(view, "#reconcile-bank", "132,48 €")
    assert has_element?(view, "#reconcile-cleared", "132,48 €")
    assert has_element?(view, "#reconcile-question", "132,48 €")

    view |> element("#reconcile-yes") |> render_click()

    assert Enum.map([first, second, by_hand], &reload(&1).cleared) ==
             [:reconciled, :reconciled, :cleared]

    assert has_element?(view, "#flash-info", "2 Buchungen abgeschlossen")
    assert has_element?(view, "#register-meta", "Abgeglichen am")
    refute has_element?(view, "#reconcile-menu")
  end

  test "a balance entered by hand counts as of today", c do
    first = cleared(c.giro, ~D[2026-10-01], 20_000)
    second = cleared(c.giro, ~D[2026-10-08], -5_000)
    view = open(c.conn, c.giro)

    assert has_element?(view, "#reconcile-question", "150,00 €")
    refute has_element?(view, "#reconcile-bank")

    enter(view, "150,00")

    assert has_element?(view, "#reconcile-banner", "Die Salden stimmen überein")
    view |> element("#reconcile-finish", "Abschließen") |> render_click()

    assert reload(first).cleared == :reconciled
    assert reload(second).cleared == :reconciled
    refute has_element?(view, "#reconcile-banner")
    assert has_element?(view, "#balance-cleared", "150,00 €")
  end

  test "clearing a transaction in reconcile mode shrinks the difference", c do
    cleared(c.giro, ~D[2026-10-01], 20_000)
    missing = transaction_fixture(account_id: c.giro.id, date: ~D[2026-10-05], amount: 1_200)
    view = open(c.conn, c.giro)

    enter(view, "212,00")

    assert has_element?(view, "#reconcile-difference", "+12,00 €")
    assert has_element?(view, "#reconcile-finish", "Ausgleichsbuchung anlegen und abschließen")

    view |> element("#tx-#{missing.id}-cleared") |> render_click()

    assert has_element?(view, "#reconcile-banner", "Die Salden stimmen überein")
    assert has_element?(view, "#reconcile-finish", "Abschließen")
    refute has_element?(view, "#reconcile-finish", "Ausgleichsbuchung")

    view |> element("#reconcile-finish") |> render_click()

    assert reload(missing).cleared == :reconciled
    assert Repo.aggregate(Transaction, :count) == 2
  end

  test "a difference becomes an adjustment", c do
    cleared(c.giro, ~D[2026-10-01], 15_000)
    view = open(c.conn, c.giro)

    enter(view, "150,42")

    assert has_element?(view, "#reconcile-difference", "+0,42 €")
    view |> element("#reconcile-finish") |> render_click()

    adjustment = Repo.get_by!(Transaction, amount: 42) |> Repo.preload(:payee)

    assert %Transaction{approved: true, cleared: :reconciled} = adjustment
    assert adjustment.payee.name == "Ausgleichsbuchung"
    assert adjustment.category_id == Categories.ready_to_assign!().id
    assert has_element?(view, "#balance-cleared", "150,42 €")
    assert has_element?(view, "#balance-working", "150,42 €")
    assert has_element?(view, "#tx-#{adjustment.id}", "Ausgleichsbuchung")
    refute has_element?(view, "#reconcile-banner")
  end

  test "a differing file balance offers to search the difference up to its date", c do
    early = cleared(c.giro, ~D[2026-10-01], 10_000)
    later = cleared(c.giro, ~D[2026-10-09], 5_000)

    {:ok, _} =
      Ledger.put_bank_balance(c.giro, %{amount: 11_000, date: ~D[2026-10-08], source: :file})

    view = open(c.conn, c.giro)

    assert has_element?(view, "#reconcile-menu", "+10,00 €")
    refute has_element?(view, "#reconcile-yes")

    view |> element("#reconcile-search") |> render_click()

    assert has_element?(view, "#reconcile-banner", "08.10.2026")
    assert has_element?(view, "#reconcile-difference", "+10,00 €")

    view |> element("#reconcile-finish") |> render_click()

    assert reload(early).cleared == :reconciled
    assert reload(later).cleared == :cleared
    assert %Transaction{date: ~D[2026-10-08]} = Repo.get_by!(Transaction, amount: 1_000)
  end

  test "finishing refuses a difference other than the one shown", c do
    transaction = cleared(c.giro, ~D[2026-10-01], 10_000)
    view = open(c.conn, c.giro)

    enter(view, "100,00")
    assert has_element?(view, "#reconcile-finish", "Abschließen")

    # Another session clears a transaction meanwhile.
    cleared(c.giro, ~D[2026-10-02], 500)
    view |> element("#reconcile-finish") |> render_click()

    assert has_element?(view, "#flash-error", "−5,00 €")
    assert has_element?(view, "#reconcile-difference", "−5,00 €")
    assert reload(transaction).cleared == :cleared
    assert Repo.aggregate(Transaction, :count) == 2
  end

  test "reconcile mode stays through search and view, and ends on another account", c do
    cleared(c.giro, ~D[2026-10-01], 10_000)
    savings = account_fixture(kind: :savings)
    view = open(c.conn, c.giro)

    enter(view, "90")
    view |> form("#register-search", %{q: "nichts"}) |> render_change()
    assert has_element?(view, "#reconcile-difference", "−10,00 €")

    render_patch(view, ~p"/accounts/#{savings}")
    refute has_element?(view, "#reconcile-banner")
  end

  test "a balance it cannot keep is refused in the popover", c do
    view = open(c.conn, c.giro)

    render_click(view, "reconcile_no", %{})
    render_submit(view, "reconcile_start", %{"balance" => %{"a" => "1"}})
    assert has_element?(view, "#reconcile-form", "Betrag ist ungültig")

    view |> form("#reconcile-form", %{balance: "100000000000,01"}) |> render_submit()
    assert has_element?(view, "#reconcile-form", "Betrag muss zwischen")
    refute has_element?(view, "#reconcile-banner")
  end

  test "cancelling reconcile mode changes nothing", c do
    transaction = cleared(c.giro, ~D[2026-10-01], 10_000)
    view = open(c.conn, c.giro)

    enter(view, "50")
    view |> element("#reconcile-cancel") |> render_click()

    refute has_element?(view, "#reconcile-banner")
    assert reload(transaction).cleared == :cleared
    assert Repo.aggregate(Transaction, :count) == 1
  end

  test "an amount it cannot read is refused in the popover", c do
    view = open(c.conn, c.giro)

    enter(view, "zwölf")

    assert has_element?(view, "#reconcile-form", "Betrag")
    refute has_element?(view, "#reconcile-banner")
  end

  test "Ja refuses when the balance changed meanwhile", c do
    cleared(c.giro, ~D[2026-10-01], 10_000)
    view = open(c.conn, c.giro)
    cleared(c.giro, ~D[2026-10-02], 500)

    view |> element("#reconcile-yes") |> render_click()

    assert has_element?(view, "#flash-error", "−5,00 €")
    assert Repo.aggregate(from(t in Transaction, where: t.cleared == :reconciled), :count) == 0
  end

  test "all accounts offer no reconcile", c do
    {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
    refute has_element?(view, "#reconcile-open")
  end
end
