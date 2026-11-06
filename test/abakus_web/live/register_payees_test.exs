defmodule AbakusWeb.RegisterPayeesTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.UsersFixtures, only: [user_scope_fixture: 0]
  import Setzkasten.Test.Confirm

  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.{Payees, Scheduled}

  setup :register_and_log_in_user

  setup do
    fix_today(~D[2026-11-06])
    giro = account_fixture(name: "💶 Girokonto", kind: :checking)
    savings = account_fixture(name: "🏦 Sparkonto", kind: :savings)
    groceries = category_fixture(name: "🛒 Lebensmittel")
    rewe = payee_fixture(name: "Rewe")
    aldi = payee_fixture(name: "Aldi")
    %{giro: giro, savings: savings, groceries: groceries, rewe: rewe, aldi: aldi}
  end

  defp book(c, payee, count \\ 1) do
    for _ <- 1..count//1,
        do: transaction_fixture(account_id: c.giro.id, payee_id: payee.id, amount: -1_000)
  end

  defp register(c, path \\ nil) do
    {:ok, view, _html} = live(c.conn, path || ~p"/budget/accounts/#{c.giro}")
    view
  end

  defp open(view) do
    view |> element("#payees-item", "Empfänger verwalten …") |> render_click()
    assert has_element?(view, "#payee-modal h2", "Empfänger verwalten")
    view
  end

  defp show(view, payee) do
    view |> element("#payee-row-#{payee.id} button") |> render_click()
    assert has_element?(view, "#payee-name", payee.name)
    view
  end

  defp rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#payee-rows button > span[title]")
    |> LazyHTML.attribute("title")
  end

  defp rules(payee),
    do:
      Payees.list(budget_scope())
      |> Enum.find(&(&1.payee.id == payee.id))
      |> Map.fetch!(:rename_conditions)
      |> Enum.map(&{&1.operator, &1.text})

  test "opens from the Ansicht menu on the selected transaction's payee", c do
    [transaction] = book(c, c.rewe)
    transfer = transaction_fixture(account_id: c.giro.id, payee_id: c.savings.transfer_payee.id)
    view = register(c)

    open(view)
    assert has_element?(view, "#payee-prompt", "Empfänger zum Bearbeiten wählen")

    render_click(view, "close_payee_dialog", %{})
    refute has_element?(view, "#payee-modal")

    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    open(view)
    assert has_element?(view, "#payee-name", "Rewe")
    assert has_element?(view, "#payee-row-#{c.rewe.id} [aria-current]")
    assert has_element?(view, "#payee-uses", "1 Buchung")

    render_click(view, "close_payee_dialog", %{})
    view |> element("#tx-#{transfer.id} td.app-payee") |> render_click()
    open(view)
    assert has_element?(view, "#payee-prompt")
  end

  test "the filter and search narrow the list; hidden payees leave the editor's payee options",
       c do
    hidden = payee_fixture(name: "Kiosk", hidden: true)
    view = c |> register() |> open()

    assert rows(view) == ["Aldi", "Rewe"]

    view |> element("#payee-filter button", "Ausgeblendete") |> render_click()
    assert rows(view) == ["Kiosk"]

    view |> element("#payee-filter button", "Alle") |> render_click()
    assert rows(view) == ["Aldi", "Kiosk", "Rewe"]
    assert has_element?(view, "#payee-row-#{hidden.id} [aria-label='Ausgeblendet']")
    refute has_element?(view, "#payee-row-#{c.aldi.id} [aria-label='Ausgeblendet']")

    view |> element("#payee-search") |> render_change(%{"q" => "ki"})
    assert rows(view) == ["Kiosk"]

    view |> element("#payee-search") |> render_change(%{"q" => ""})
    view |> show(c.aldi) |> element("#payee-listed-form") |> render_change(%{"listed" => "false"})
    assert Repo.reload(c.aldi).hidden
    assert has_element?(view, "#payee-row-#{c.aldi.id} [aria-label='Ausgeblendet']")

    render_click(view, "close_payee_dialog", %{})
    view |> element("#new-transaction") |> render_click()
    assert render(view) =~ ~s|data-value="p:Rewe"|
    refute render(view) =~ ~s|data-value="p:Aldi"|
  end

  test "setting and clearing a payee's category changes what the editor fills in", c do
    view = c |> register() |> open() |> show(c.rewe)

    view |> element("#payee-category-form") |> render_change(%{"category_id" => c.groceries.id})
    assert Repo.reload(c.rewe).last_category_id == c.groceries.id

    render_click(view, "close_payee_dialog", %{})
    view |> element("#new-transaction") |> render_click()
    pick_payee(view, "p:Rewe")
    assert category?(view, c.groceries.id)

    render_click(view, "cancel_edit", %{})
    view |> open() |> show(c.rewe)
    view |> element("#payee-category-form") |> render_change(%{"category_id" => ""})
    assert Repo.reload(c.rewe).last_category_id == nil

    render_click(view, "close_payee_dialog", %{})
    view |> element("#new-transaction") |> render_click()
    pick_payee(view, "p:Rewe")
    refute category?(view, c.groceries.id)
  end

  defp pick_payee(view, value) do
    view
    |> element("#tx-form")
    |> render_change(%{
      "transaction" => %{"payee_pick" => value},
      "_target" => ["transaction", "payee_pick"]
    })
  end

  defp category?(view, id),
    do: has_element?(view, ~s|#tx-category-combobox input[data-value-input][value="#{id}"]|)

  test "(in N Buchungen) closes the modal and searches Alle Konten for the payee", c do
    book(c, c.rewe, 2)
    view = c |> register() |> open() |> show(c.rewe)

    view |> element("#payee-uses", "2 Buchungen") |> render_click()
    assert_patch(view, ~p"/budget/accounts/all?q=Rewe")
    refute has_element?(view, "#payee-modal")
    assert has_element?(view, "#register-q[value='Rewe']")
  end

  test "renaming to an existing name merges, errors stay at the field", c do
    markt = payee_fixture(name: "REWE Markt GmbH")
    book(c, c.rewe, 3)
    book(c, markt, 2)
    view = c |> register() |> open() |> show(markt)

    view |> element("#payee-rename") |> render_click()
    assert has_element?(view, "#payee-rename-name[phx-hook][data-escape*='cancel_rename']")
    view |> form("#payee-rename-form", name: "Transfer : Giro") |> render_submit()

    assert has_element?(
             view,
             "#payee-rename-form",
             "„Transfer : Giro“ ist kein gültiger Empfängername. „Transfer :“ am Anfang"
           )

    view |> form("#payee-rename-form", name: "rewe") |> render_submit()
    assert has_element?(view, "#payee-name", "Rewe")
    assert has_element?(view, "#payee-uses", "5 Buchungen")
    refute has_element?(view, "#payee-row-#{markt.id}")
    assert rules(c.rewe) == [{:is, "REWE Markt GmbH"}]
    assert has_element?(view, "#payee-row-#{c.rewe.id} .font-semibold")
  end

  test "combines the selected payees under the new name", c do
    nord = payee_fixture(name: "Aldi Nord")
    dank = payee_fixture(name: "ALDI SAGT DANKE")
    book(c, nord)
    book(c, dank, 2)
    book(c, c.aldi, 4)
    view = c |> register() |> open() |> show(nord)

    view |> element("#payee-row-#{dank.id}-check") |> render_click()
    view |> element("#payee-row-#{c.aldi.id}-check") |> render_click()
    assert has_element?(view, "#payee-multiple-title", "3 Empfänger ausgewählt")
    assert has_element?(view, "#payee-multiple-names", "„Aldi Nord“, „ALDI SAGT DANKE“, „Aldi“")
    assert has_element?(view, "#payee-combine-name[value='ALDI SAGT DANKE']")

    view |> form("#payee-combine-form", name: "Aldi") |> render_submit()
    assert has_element?(view, "#payee-name", "Aldi")
    assert has_element?(view, "#payee-uses", "7 Buchungen")
    assert rows(view) == ["Aldi", "Rewe"]
    assert Enum.sort(rules(c.aldi)) == [{:is, "ALDI SAGT DANKE"}, {:is, "Aldi Nord"}]
  end

  test "hides and lists the selected payees", c do
    view = c |> register() |> open() |> show(c.aldi)
    view |> element("#payee-row-#{c.rewe.id}-check") |> render_click()

    view |> element("#payee-hide-selected") |> render_click()
    assert Repo.reload(c.aldi).hidden and Repo.reload(c.rewe).hidden
    assert rows(view) == []
    assert has_element?(view, "#payee-rows-empty", "Keine Empfänger")

    view |> element("#payee-show-selected") |> render_click()
    refute Repo.reload(c.aldi).hidden or Repo.reload(c.rewe).hidden
  end

  test "rules save at once and blank ones are dropped", c do
    view = c |> register() |> open() |> show(c.rewe)
    refute has_element?(view, "#payee-rename-existing")

    view |> element("#payee-add-rule") |> render_click()
    [key] = rule_keys(view)

    type_rule(view, key, "starts_with", "REWE Markt")
    assert rules(c.rewe) == [{:starts_with, "REWE Markt"}]
    assert has_element?(view, "#payee-row-#{c.rewe.id} .font-semibold")

    view |> element("#payee-rule-#{key}-add") |> render_click()
    assert length(rule_keys(view)) == 2
    assert has_element?(view, "#payee-rename-existing[disabled]")

    render_click(view, "close_payee_dialog", %{})
    assert rules(c.rewe) == [{:starts_with, "REWE Markt"}]

    view |> open() |> show(c.rewe)
    [key] = rule_keys(view)
    view |> element("#payee-rule-#{key}-remove") |> render_click()
    assert rules(c.rewe) == []
  end

  defp type_rule(view, key, operator, text) do
    view
    |> element("#payee-rules-form")
    |> render_change(%{"rules" => %{key => %{"operator" => operator, "text" => text}}})
  end

  defp rule_keys(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#payee-rules-form > [id^='payee-rule-']")
    |> LazyHTML.attribute("id")
    |> Enum.map(&String.replace_prefix(&1, "payee-rule-", ""))
  end

  test "Bestehende Buchungen umbenennen asks with the preview, or says nothing matches", c do
    {:ok, _rules} =
      Payees.put_rename_conditions(budget_scope(), c.rewe, [
        %{operator: :starts_with, text: "REWE Markt"}
      ])

    gmbh = payee_fixture(name: "REWE Markt GmbH 4711")
    koeln = payee_fixture(name: "REWE Markt Köln")
    book(c, gmbh, 3)
    book(c, koeln)
    view = c |> register() |> open() |> show(c.rewe)

    asked = asked(view, "#payee-rename-existing")
    assert asked.question == "Bei 4 Buchungen wird der Empfänger in „Rewe“ umbenannt:"
    assert asked.text == "Betroffene Empfänger: „REWE Markt GmbH 4711“, „REWE Markt Köln“"
    assert asked.label == "Umbenennen"

    confirm_click(view, "#payee-rename-existing")
    assert has_element?(view, "#payee-uses", "4 Buchungen")

    assert Ledger.list_transactions(budget_scope(), c.giro)
           |> Enum.all?(&(&1.payee_id == c.rewe.id))

    assert alerted(view, "#payee-rename-existing") == %{
             title: "Keine Buchungen zum Umbenennen gefunden.",
             text: "Diese Regeln treffen auf keinen Empfänger einer Buchung zu."
           }
  end

  test "Bestehende Buchungen umbenennen asks about and folds in a matching payee nothing uses",
       c do
    booking = payee_fixture(name: "Booking.com")

    {:ok, _rules} =
      Payees.put_rename_conditions(budget_scope(), booking, [
        %{operator: :starts_with, text: "Partners on Booking BV"}
      ])

    partners = payee_fixture(name: "Partners on Booking BV, Amsterdam; NL")
    view = c |> register() |> open() |> show(booking)

    asked = asked(view, "#payee-rename-existing")
    assert asked.question == "Empfänger in „Booking.com“ umbenennen?"
    assert asked.text == "Betroffene Empfänger: „Partners on Booking BV, Amsterdam; NL“"
    assert asked.label == "Umbenennen"

    confirm_click(view, "#payee-rename-existing")
    assert Repo.reload(partners).successor_id == booking.id
    refute has_element?(view, "#payee-row-#{partners.id}")
  end

  test "Bestehende Buchungen umbenennen renames only what it asked about", c do
    {:ok, _rules} =
      Payees.put_rename_conditions(budget_scope(), c.rewe, [
        %{operator: :starts_with, text: "REWE Markt"}
      ])

    view = c |> register() |> open() |> show(c.rewe)
    gmbh = payee_fixture(name: "REWE Markt GmbH 4711")
    book(c, gmbh)

    assert alerted(view, "#payee-rename-existing").title ==
             "Keine Buchungen zum Umbenennen gefunden."

    synced(view)
    assert Repo.reload(gmbh).deleted_at == nil

    assert asked(view, "#payee-rename-existing").question ==
             "Bei 1 Buchung wird der Empfänger in „Rewe“ umbenannt:"

    koeln = payee_fixture(name: "REWE Markt Köln")
    book(c, koeln)
    confirm_click(view, "#payee-rename-existing")
    assert Repo.reload(gmbh).deleted_at == nil and Repo.reload(koeln).deleted_at == nil
    assert asked(view, "#payee-rename-existing").text =~ "„REWE Markt Köln“"

    confirm_click(view, "#payee-rename-existing")
    assert Repo.reload(gmbh).successor_id == c.rewe.id
    assert Repo.reload(koeln).successor_id == c.rewe.id
  end

  test "a rename keeps the old name's rule through the next rule edit", c do
    markt = payee_fixture(name: "REWE Markt")
    view = c |> register() |> open() |> show(markt)

    view |> element("#payee-rename") |> render_click()
    view |> form("#payee-rename-form", name: "Rewe Köln") |> render_submit()
    assert has_element?(view, "#payee-name", "Rewe Köln")
    assert [key] = rule_keys(view)

    view |> element("#payee-add-rule") |> render_click()
    [^key, added] = rule_keys(view)
    type_rule(view, added, "contains", "Köln")

    assert rules(markt) == [{:is, "REWE Markt"}, {:contains, "Köln"}]
  end

  test "a rule text over 200 characters is refused at the field", c do
    view = c |> register() |> open() |> show(c.rewe)
    view |> element("#payee-add-rule") |> render_click()
    [key] = rule_keys(view)

    type_rule(view, key, "contains", String.duplicate("a", 201))
    assert has_element?(view, "#payee-rule-#{key}-text[aria-invalid]")
    assert has_element?(view, "#payee-rule-#{key}", "Darf höchstens 200 Zeichen lang sein")
    assert rules(c.rewe) == []
  end

  test "opening on a hidden payee shows all payees", c do
    hidden = payee_fixture(name: "Kiosk", hidden: true)
    [transaction] = book(c, hidden)
    view = register(c)

    view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
    open(view)
    assert has_element?(view, "#payee-filter [aria-pressed='true']", "Alle")
    assert has_element?(view, "#payee-row-#{hidden.id} [aria-current]")
  end

  test "(in N Buchungen) opens the scheduled transactions when some use the payee", c do
    {:ok, _scheduled} =
      Scheduled.create(budget_scope(), %{
        account_id: c.giro.id,
        next_date: ~D[2026-12-01],
        repeat_unit: :month,
        repeat_every: 1,
        payee_id: c.rewe.id,
        amount: -500
      })

    book(c, c.aldi)
    view = c |> register() |> open() |> show(c.aldi)
    view |> element("#payee-uses") |> render_click()
    refute has_element?(view, "#scheduled-list[open]")

    view |> open() |> show(c.rewe)
    view |> element("#payee-uses") |> render_click()
    assert_patch(view, ~p"/budget/accounts/all?q=Rewe")
    assert has_element?(view, "#scheduled-list[open]")

    view |> open() |> show(c.aldi)
    view |> element("#payee-uses") |> render_click()
    assert has_element?(view, "#scheduled-list[open]")
  end

  test "changes from another device reload the dialog; a payee that is gone is let go", c do
    view = c |> register() |> open() |> show(c.rewe)

    {:ok, _rules} =
      Payees.put_rename_conditions(budget_scope(), c.rewe, [%{operator: :is, text: "REWE"}])

    edeka = payee_fixture(name: "Edeka")
    synced(view)
    assert rows(view) == ["Aldi", "Edeka", "Rewe"]
    assert [_key] = rule_keys(view)

    {:ok, _aldi} = Payees.rename(budget_scope(), c.rewe, "Aldi")
    synced(view)
    assert has_element?(view, "#payee-prompt")
    assert rows(view) == ["Aldi", "Edeka"]

    show(view, edeka)
    {:ok, _aldi} = Payees.rename(budget_scope(), edeka, "Aldi")

    view |> element("#payee-category-form") |> render_change(%{"category_id" => c.groceries.id})
    assert render(view) =~ "Den Empfänger gibt es nicht mehr."
    assert has_element?(view, "#payee-prompt")
    assert Repo.reload(edeka).last_category_id == nil
  end

  # The register passes the sync on with send_update, which arrives after the next render.
  defp synced(view) do
    send(view.pid, {:synced, "other"})
    render(view)
  end

  test "a write to a payee gone under the shown one is refused with a message", c do
    view = c |> register() |> open() |> show(c.rewe)
    {:ok, _aldi} = Payees.rename(budget_scope(), c.rewe, "Aldi")

    view |> element("#payee-add-rule") |> render_click()
    [key] = rule_keys(view)
    type_rule(view, key, "contains", "REWE")

    assert render(view) =~ "Den Empfänger gibt es nicht mehr."
    assert has_element?(view, "#payee-prompt")
  end

  test "another user's payee cannot be shown, selected or written", c do
    other = user_scope_fixture()
    {:ok, theirs} = Ledger.create_payee(other, %{name: "Fremd"})
    view = c |> register() |> open()

    view |> with_target("#payee-dialog") |> render_click("show", %{"id" => theirs.id})
    assert has_element?(view, "#payee-prompt")
    view |> with_target("#payee-dialog") |> render_click("toggle", %{"id" => theirs.id})
    view |> with_target("#payee-dialog") |> render_click("set_listed", %{"listed" => "false"})
    view |> with_target("#payee-dialog") |> render_submit("combine", %{"name" => "Meins"})

    assert %{name: "Fremd", hidden: false, deleted_at: nil} = Repo.reload(theirs)
  end
end
