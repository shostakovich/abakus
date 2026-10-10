defmodule AbakusWeb.RegisterLive.TransactionEditor do
  @moduledoc """
  Edits a transaction as YNAB does, for a new one and an existing one alike. On desktops (`layout: :row`) it
  replaces the transaction's rows in the register: inputs in every column, a split's subtransactions as rows
  below, Cancel and Save (Approve for one waiting for approval) underneath; its root is a `<tbody>` and its inputs
  belong to `#tx-form` by their `form` attribute. Phones (`layout: :sheet`) get a sheet from the bottom with the
  amount first. The form's state is `AbakusWeb.TransactionForm` params.

  Payee and category are comboboxes (the `Combobox` hook) whose options come once from a `<template>`; a pick
  arrives as the event `pick`. Transfers are picked as payees, the other open accounts above the payees, in a
  split's subtransactions too. A payee suggests its last category, and a suggestion goes again when the payee
  changes; a chosen category stays. A transfer between a budget and a tracking account takes a category and
  suggests the one last used between the two. Changing or deleting a reconciled transaction, or one whose
  counterpart is, asks first.

  Tells its LiveView `{TransactionEditor, :done, message}` once the transaction is saved or deleted; the events
  `cancel_edit` (Cancel, Escape) go to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Categories, Ledger, Names}
  alias Abakus.Ledger.{Account, Transaction}
  alias AbakusWeb.{AccountGroups, CategoryOptions, Format, TransactionForm}
  alias AbakusWeb.RegisterLive.Components

  @main "main"

  @labels %{
    account_id: "Konto",
    date: "Datum",
    amount: "Betrag",
    payee_id: "Empfänger",
    category_id: "Kategorie",
    counterpart_category_id: "Kategorie",
    memo: "Memo",
    cleared: "Buchung",
    name: "Empfänger",
    transfer_transaction_id: "Gegenbuchung",
    transfer_subtransaction_id: "Buchung",
    matched_transaction_id: "Zugeordnete Buchung"
  }

  @impl true
  def render(%{layout: :sheet} = assigns) do
    assigns = assign(assigns, :subtransactions, TransactionForm.subtransactions(assigns.params))

    ~H"""
    <div id={@id}>
      <div class="modal-backdrop show"></div>
      <div
        class="modal d-block app-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="tx-title"
        phx-window-keydown="cancel_edit"
        phx-key="Escape"
      >
        <div class="modal-dialog modal-dialog-scrollable app-sheet">
          <.form
            for={%{}}
            id="tx-form"
            class="modal-content"
            phx-change="change"
            phx-submit="save"
            phx-target={@myself}
            phx-mounted={is_nil(@transaction) && JS.focus(to: "#tx-amount")}
          >
            <div class="modal-header">
              <h2 class="modal-title h5" id="tx-title">
                {if @transaction, do: "Buchung bearbeiten", else: "Neue Buchung"}
              </h2>
              <button type="button" class="btn-close" aria-label="Schließen" phx-click="cancel_edit"></button>
            </div>
            <div class="modal-body">
              <.notes
                split_of={@split_of}
                transaction={@transaction}
                accounts={@accounts}
                error={@error}
              />
              <div class="mb-3">
                <label class="form-label" for="tx-amount">Betrag</label>
                <div class="input-group">
                  <button
                    id="tx-sign"
                    type="button"
                    class={["btn btn-outline-secondary app-sign", sign_class(@params["sign"])]}
                    aria-label={sign_label(@params["sign"])}
                    title={sign_label(@params["sign"])}
                    phx-click="toggle_sign"
                    phx-target={@myself}
                  >
                    {if @params["sign"] == "+", do: "+", else: "−"}
                  </button>
                  <.directed_amount
                    id="tx-amount"
                    name="transaction"
                    side={@params}
                    sign={@params["sign"]}
                    class="form-control text-end app-q app-tx-amount-input"
                  />
                  <span class="input-group-text">€</span>
                </div>
              </div>
              <div class="mb-3">
                <label class="form-label" for="tx-payee">Empfänger</label>
                <.payee_combo id="tx-payee" name="transaction" side={@main} {combo_assigns(assigns)} />
              </div>
              <div class="mb-3">
                <label class="form-label" for="tx-category">Kategorie</label>
                <.category_cell id="tx-category" side={@main} {combo_assigns(assigns)} />
              </div>
              <div :if={@params["split"] == "true"} class="mb-3">
                <div
                  :for={{index, sub} <- @subtransactions}
                  id={"tx-sub-#{index}"}
                  class="border rounded p-2 mb-2"
                >
                  <div class="d-flex gap-2 mb-2">
                    <div class="flex-grow-1 app-min-w-0">
                      <.payee_combo
                        id={"tx-sub-#{index}-payee"}
                        name={sub_name(index)}
                        side={index}
                        {combo_assigns(assigns)}
                      />
                    </div>
                    <.remove_button index={index} target={@myself} />
                  </div>
                  <div class="mb-2">
                    <.category_cell
                      id={"tx-sub-#{index}-category"}
                      side={index}
                      {combo_assigns(assigns)}
                    />
                  </div>
                  <div class="d-flex gap-2">
                    <input
                      id={"tx-sub-#{index}-memo"}
                      name={sub_name(index, "memo")}
                      value={sub["memo"]}
                      class="form-control form-control-sm"
                      placeholder="Memo"
                      autocomplete="off"
                      phx-debounce="300"
                    />
                    <div class="input-group input-group-sm app-tx-sub-amount">
                      <.directed_amount
                        id={"tx-sub-#{index}-amount"}
                        name={sub_name(index)}
                        side={sub}
                        sign={@params["sign"]}
                        class="form-control text-end app-q"
                      />
                      <span class="input-group-text">€</span>
                    </div>
                  </div>
                </div>
                <div class="d-flex align-items-center gap-2">
                  <.add_button target={@myself} />
                  <span id="tx-remainder" class="small ms-auto app-q">
                    <.remainder amount={directed_remainder(@params)} />
                  </span>
                </div>
              </div>
              <div class="row g-3">
                <div class="col-6">
                  <label class="form-label" for="tx-date">Datum</label>
                  <.date_input value={@params["date"]} />
                </div>
                <div :if={@columns.all} class="col-6">
                  <label class="form-label" for="tx-account">Konto</label>
                  <.account_select options={account_options(assigns)} value={@params["account_id"]} />
                </div>
                <div class="col-12">
                  <label class="form-label" for="tx-memo">
                    Memo <span class="text-body-secondary">(optional)</span>
                  </label>
                  <input
                    id="tx-memo"
                    name="transaction[memo]"
                    value={@params["memo"]}
                    class="form-control"
                    autocomplete="off"
                    phx-debounce="300"
                  />
                </div>
              </div>
              <.templates {combo_assigns(assigns)} />
            </div>
            <div class="modal-footer">
              <button
                :if={@transaction}
                id="tx-delete"
                type="button"
                class="btn btn-outline-danger me-auto"
                phx-click="delete"
                phx-target={@myself}
                phx-value-reconciled={@locked && "confirmed"}
                data-confirm={
                  if @locked,
                    do: "Diese Buchung ist abgeschlossen. Trotzdem löschen?",
                    else: "Buchung löschen?"
                }
              >
                Löschen
              </button>
              <.save_buttons transaction={@transaction} locked={@locked} sheet />
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        subtransactions: TransactionForm.subtransactions(assigns.params),
        remainder: TransactionForm.remainder(assigns.params)
      )

    ~H"""
    <tbody
      id={@id}
      class="app-edit"
      phx-hook="EditRow"
      data-focus={@focus}
      phx-window-keydown="cancel_edit"
      phx-key="Escape"
    >
      <tr class="app-edit-main">
        <td class="app-pick">
          <input type="checkbox" class="form-check-input" checked={!!@transaction} disabled />
        </td>
        <td class="app-flag-col"></td>
        <td class="app-edit-date"><.date_input value={@params["date"]} small /></td>
        <td :if={@columns.all} class="app-konto">
          <.account_select options={account_options(assigns)} value={@params["account_id"]} small />
        </td>
        <td class="app-payee">
          <.payee_combo id="tx-payee" name="transaction" side={@main} small {combo_assigns(assigns)} />
          <.category_below id="tx-category" side={@main} columns={@columns} {combo_assigns(assigns)} />
        </td>
        <td :if={@columns.category} class="app-catcol">
          <.category_cell id="tx-category" side={@main} small {combo_assigns(assigns)} />
        </td>
        <td class="app-memo-col">
          <input
            id="tx-memo"
            form="tx-form"
            name="transaction[memo]"
            value={@params["memo"]}
            class="form-control form-control-sm"
            placeholder="Memo"
            autocomplete="off"
            size="1"
            phx-debounce="300"
          />
        </td>
        <td class="app-out">
          <.amount_input
            id="tx-outflow"
            name="transaction[outflow]"
            value={@params["outflow"]}
            placeholder="Ausgang"
          />
        </td>
        <td class="app-in">
          <.amount_input
            id="tx-inflow"
            name="transaction[inflow]"
            value={@params["inflow"]}
            placeholder="Eingang"
          />
        </td>
        <td :if={@columns.running}></td>
        <td class="app-c-col"></td>
      </tr>
      <tr :for={{index, sub} <- @subtransactions} id={"tx-sub-#{index}"} class="app-edit-sub">
        <td></td>
        <td></td>
        <td class="text-end">
          <.remove_button index={index} target={@myself} />
        </td>
        <td :if={@columns.all}></td>
        <td class="app-payee">
          <.payee_combo
            id={"tx-sub-#{index}-payee"}
            name={sub_name(index)}
            side={index}
            small
            {combo_assigns(assigns)}
          />
          <.category_below
            id={"tx-sub-#{index}-category"}
            side={index}
            columns={@columns}
            {combo_assigns(assigns)}
          />
        </td>
        <td :if={@columns.category} class="app-catcol">
          <.category_cell id={"tx-sub-#{index}-category"} side={index} small {combo_assigns(assigns)} />
        </td>
        <td class="app-memo-col">
          <input
            id={"tx-sub-#{index}-memo"}
            form="tx-form"
            name={sub_name(index, "memo")}
            value={sub["memo"]}
            class="form-control form-control-sm"
            placeholder="Memo"
            autocomplete="off"
            size="1"
            phx-debounce="300"
          />
        </td>
        <td class="app-out">
          <.amount_input
            id={"tx-sub-#{index}-outflow"}
            name={sub_name(index, "outflow")}
            value={sub["outflow"]}
            placeholder="Ausgang"
          />
        </td>
        <td class="app-in">
          <.amount_input
            id={"tx-sub-#{index}-inflow"}
            name={sub_name(index, "inflow")}
            value={sub["inflow"]}
            placeholder="Eingang"
          />
        </td>
        <td :if={@columns.running}></td>
        <td></td>
      </tr>
      <tr :if={@params["split"] == "true"} class="app-edit-rest">
        <td colspan={3 + if(@columns.all, do: 1, else: 0)}></td>
        <td><.add_button target={@myself} /></td>
        <td :if={@columns.category}></td>
        <td class="text-end small text-body-secondary">Noch aufzuteilen</td>
        <td
          id="tx-remainder-out"
          class={["text-end app-q", remainder_class(@remainder && -@remainder)]}
        >
          {@remainder && Format.amount(max(-@remainder, 0))}
        </td>
        <td id="tx-remainder-in" class={["text-end app-q", remainder_class(@remainder)]}>
          {@remainder && Format.amount(max(@remainder, 0))}
        </td>
        <td :if={@columns.running}></td>
        <td></td>
      </tr>
      <tr class="app-edit-actions">
        <td colspan={@columns.count}>
          <.form
            for={%{}}
            id="tx-form"
            class="d-flex flex-wrap align-items-center justify-content-end gap-2"
            phx-change="change"
            phx-submit="save"
            phx-target={@myself}
          >
            <.notes
              split_of={@split_of}
              transaction={@transaction}
              accounts={@accounts}
              error={@error}
            />
            <.templates {combo_assigns(assigns)} />
            <.save_buttons transaction={@transaction} locked={@locked} small />
          </.form>
        </td>
      </tr>
    </tbody>
    """
  end

  attr :split_of, :boolean, required: true
  attr :transaction, :any, required: true
  attr :accounts, :map, required: true
  attr :error, :string, default: nil

  defp notes(assigns) do
    ~H"""
    <div :if={@split_of} id="tx-split-of" class="small text-body-secondary me-auto">
      Teil einer Aufteilung in {@accounts[@transaction.account_id].name}; hier steht die ganze Aufteilung.
    </div>
    <div
      :if={@error}
      id="tx-error"
      class="alert alert-danger py-1 px-2 mb-0 small me-auto"
      role="alert"
    >
      {@error}
    </div>
    """
  end

  attr :transaction, :any, required: true
  attr :locked, :boolean, required: true
  attr :small, :boolean, default: false

  attr :sheet, :boolean,
    default: false,
    doc: "phones close the sheet with the ×, three buttons do not fit"

  defp save_buttons(assigns) do
    ~H"""
    <input :if={@locked} type="hidden" name="reconciled" value="confirmed" />
    <button
      id="tx-cancel"
      type="button"
      class={["btn btn-light", @small && "btn-sm", @sheet && "d-none d-sm-inline-block"]}
      phx-click="cancel_edit"
    >
      Abbrechen
    </button>
    <button
      id="tx-save"
      type="submit"
      class={["btn btn-primary", @small && "btn-sm"]}
      phx-disable-with="Speichern …"
      data-confirm={@locked && "Diese Buchung ist abgeschlossen. Trotzdem ändern?"}
    >
      {if @transaction && !@transaction.approved, do: "Bestätigen", else: "Speichern"}
    </button>
    """
  end

  attr :value, :string, required: true
  attr :small, :boolean, default: false

  defp date_input(assigns) do
    ~H"""
    <input
      id="tx-date"
      type="date"
      form="tx-form"
      name="transaction[date]"
      value={@value}
      class={["form-control", @small && "form-control-sm"]}
      aria-label="Datum"
      required
    />
    """
  end

  attr :options, :list, required: true
  attr :value, :string, required: true
  attr :small, :boolean, default: false

  defp account_select(assigns) do
    ~H"""
    <select
      id="tx-account"
      form="tx-form"
      name="transaction[account_id]"
      class={["form-select", @small && "form-select-sm"]}
      aria-label="Konto"
    >
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
    </select>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :placeholder, :string, required: true

  defp amount_input(assigns) do
    ~H"""
    <input
      id={@id}
      form="tx-form"
      name={@name}
      value={@value}
      class="form-control form-control-sm text-end app-q"
      inputmode="decimal"
      placeholder={@placeholder}
      aria-label={@placeholder}
      autocomplete="off"
      size="1"
      phx-debounce="300"
    />
    """
  end

  # The phone's one amount: the column the sign picks, the other one emptied.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :side, :map, required: true
  attr :sign, :string, required: true
  attr :class, :string, required: true

  defp directed_amount(assigns) do
    {column, other} =
      if assigns.sign == "+", do: {"inflow", "outflow"}, else: {"outflow", "inflow"}

    assigns = assign(assigns, column: column, other: other)

    ~H"""
    <input type="hidden" form="tx-form" name={"#{@name}[#{@other}]"} value="" />
    <input
      id={@id}
      form="tx-form"
      name={"#{@name}[#{@column}]"}
      value={TransactionForm.directed(@side, @sign)}
      class={@class}
      inputmode="decimal"
      placeholder="0,00"
      aria-label="Betrag"
      autocomplete="off"
      phx-debounce="300"
    />
    """
  end

  attr :index, :string, required: true
  attr :target, :any, required: true

  defp remove_button(assigns) do
    ~H"""
    <button
      id={"tx-sub-#{@index}-remove"}
      type="button"
      class="btn btn-sm btn-link text-body-secondary p-0 app-sub-remove"
      aria-label="Teil entfernen"
      title="Teil entfernen"
      phx-click="remove_subtransaction"
      phx-value-index={@index}
      phx-target={@target}
    >
      −
    </button>
    """
  end

  attr :target, :any, required: true

  defp add_button(assigns) do
    ~H"""
    <button
      id="tx-add-sub"
      type="button"
      class="btn btn-sm btn-link text-decoration-none text-start p-0 d-inline-flex align-items-center gap-1"
      phx-click="add_subtransaction"
      phx-target={@target}
    >
      <.icon name="plus" class="app-icon-sm" /> Teil hinzufügen
    </button>
    """
  end

  attr :amount, :integer, default: nil

  defp remainder(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@amount) -> %>
      <% @amount == 0 -> %>
        <span class="text-success">Aufteilung stimmt</span>
      <% true -> %>
        Noch aufzuteilen: <strong class={@amount < 0 && "app-neg"}>{Format.euros(@amount)}</strong>
    <% end %>
    """
  end

  # What the comboboxes of a side need.
  defp combo_assigns(assigns) do
    Map.take(assigns, [:params, :accounts, :categories, :payees, :myself])
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :small, :boolean, default: false

  defp payee_combo(assigns) do
    side = TransactionForm.side(assigns.params, assigns.side)
    transfer = assigns.accounts[TransactionForm.to_id(side["transfer_account_id"])]

    assigns =
      assign(assigns,
        values: side,
        text: if(transfer, do: TransactionForm.transfer_label(transfer), else: side["payee"])
      )

    ~H"""
    <div
      id={"#{@id}-combo"}
      class="app-combo"
      phx-hook="Combobox"
      data-options="tx-payee-options"
      data-side={@side}
      data-field="payee"
      data-value={
        if @values["transfer_account_id"] != "",
          do: "a:#{@values["transfer_account_id"]}",
          else: "p:#{@text}"
      }
      data-label={@text}
    >
      <input
        id={@id}
        form="tx-form"
        type="text"
        name={"#{@name}[payee]"}
        value={@text}
        class={["form-control", @small && "form-control-sm"]}
        role="combobox"
        aria-label="Empfänger"
        aria-autocomplete="list"
        aria-controls={"#{@id}-list"}
        placeholder="Empfänger"
        autocomplete="off"
        size="1"
        phx-debounce="blur"
      />
      <div id={"#{@id}-list"} class="app-combo-menu" role="listbox" phx-update="ignore"></div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :categories, :list, required: true
  attr :myself, :any, required: true
  attr :small, :boolean, default: false

  # The category of a side: a combobox where it takes one, else what stands there instead.
  defp category_cell(assigns) do
    side = TransactionForm.side(assigns.params, assigns.side)
    option = CategoryOptions.find(assigns.categories, TransactionForm.to_id(side["category_id"]))

    assigns =
      assign(assigns,
        values: side,
        option: option,
        category?: TransactionForm.category?(assigns.params, assigns.side, assigns.accounts),
        split?: assigns.side == "main" and assigns.params["split"] == "true"
      )

    ~H"""
    <%= cond do %>
      <% @split? -> %>
        <span id={@id} class="d-block small text-body-secondary text-truncate">
          Aufgeteilt (mehrere Kategorien)
        </span>
      <% !@category? -> %>
        <input
          id={@id}
          type="text"
          class={["form-control app-combo-none", @small && "form-control-sm"]}
          placeholder={none_placeholder(@values)}
          aria-label="Kategorie"
          size="1"
          readonly
          tabindex="-1"
        />
      <% true -> %>
        <div
          id={"#{@id}-combo"}
          class="app-combo"
          phx-hook="Combobox"
          data-options="tx-category-options"
          data-side={@side}
          data-field="category"
          data-value={@values["category_id"]}
          data-label={@option && @option.text}
          data-save="tx-save"
          data-split={@side == "main" and !TransactionForm.transfer?(@values) and "true"}
        >
          <input
            id={@id}
            type="text"
            value={@option && @option.text}
            class={["form-control", @small && "form-control-sm"]}
            role="combobox"
            aria-label="Kategorie"
            aria-autocomplete="list"
            aria-controls={"#{@id}-list"}
            placeholder="Kategorie"
            autocomplete="off"
            size="1"
          />
          <div id={"#{@id}-list"} class="app-combo-menu" role="listbox" phx-update="ignore"></div>
        </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :columns, :map, required: true
  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :categories, :list, required: true
  attr :payees, :list, required: true
  attr :myself, :any, required: true

  # A tracking account's register has no category column, so a side that takes one there (a transfer to a budget
  # account, or a part of a split opened from its counterpart) has it below the payee.
  defp category_below(assigns) do
    ~H"""
    <div
      :if={!@columns.category and TransactionForm.category?(@params, @side, @accounts)}
      class="mt-1"
    >
      <.category_cell
        id={@id}
        side={@side}
        small
        params={@params}
        accounts={@accounts}
        categories={@categories}
        myself={@myself}
      />
    </div>
    """
  end

  defp none_placeholder(side) do
    if TransactionForm.transfer?(side), do: "Keine Kategorie nötig", else: ""
  end

  attr :params, :map, required: true
  attr :accounts, :map, required: true
  attr :categories, :list, required: true
  attr :payees, :list, required: true
  attr :myself, :any, required: true

  # The options of the comboboxes, once for all sides; "Aufteilen" shows for the transaction's own category only.
  defp templates(assigns) do
    assigns = assign(assigns, :transfers, transfer_options(assigns.params, assigns.accounts))

    ~H"""
    <template id="tx-payee-options">
      <div class="app-combo-opt app-combo-create" role="option" data-create>
        Empfänger „<span></span>“ anlegen
      </div>
      <div :if={@transfers != []} class="app-combo-group" role="group" aria-label="Umbuchungen">
        <div class="app-combo-head">Umbuchungen</div>
        <div
          :for={account <- @transfers}
          class="app-combo-opt"
          role="option"
          data-value={"a:#{account.id}"}
          data-key={Names.lookup_key(account.name)}
          data-label={TransactionForm.transfer_label(account)}
        >
          {TransactionForm.transfer_label(account)}
        </div>
      </div>
      <div class="app-combo-group" role="group" aria-label="Empfänger">
        <div class="app-combo-head">Empfänger</div>
        <div
          :for={payee <- @payees}
          class="app-combo-opt"
          role="option"
          data-value={"p:#{payee.name}"}
          data-key={payee.lookup_key}
          data-label={payee.name}
        >
          {payee.name}
        </div>
      </div>
    </template>
    <Components.category_template id="tx-category-options" categories={@categories}>
      <div class="app-combo-foot" data-split-only>
        <button
          id="tx-split"
          type="button"
          class="btn btn-sm btn-light w-100"
          phx-click="split"
          phx-target={@myself}
        >
          Aufteilen
        </button>
      </div>
    </Components.category_template>
    """
  end

  defp remainder_class(left) when is_integer(left) and left > 0, do: "app-neg"
  defp remainder_class(_none), do: "text-body-secondary"

  defp sub_name(index), do: "transaction[subtransactions][#{index}]"
  defp sub_name(index, field), do: "#{sub_name(index)}[#{field}]"

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    key = assigns.transaction && assigns.transaction.id

    if Map.get(socket.assigns, :loaded) == {key},
      do: {:ok, socket},
      else: {:ok, load(socket, key)}
  end

  defp load(socket, key) do
    %{transaction: transaction, accounts: accounts} = socket.assigns
    payees = Ledger.list_payees()

    assign(socket,
      loaded: {key},
      main: @main,
      params: initial_params(socket.assigns),
      suggested: MapSet.new(),
      error: nil,
      payees: payees,
      payees_by_key: Map.new(payees, &{&1.lookup_key, &1}),
      ready_to_assign_id: Categories.ready_to_assign!().id,
      categories: CategoryOptions.build(socket.assigns.today),
      locked: locked?(transaction),
      kept_accounts: kept_accounts(transaction, accounts)
    )
  end

  defp initial_params(%{transaction: nil} = assigns),
    do: TransactionForm.new(default_account_id(assigns), assigns.today)

  defp initial_params(%{transaction: transaction}),
    do: TransactionForm.from_transaction(transaction)

  # The register's account if it takes manual entries, else the first that does, budget accounts first.
  defp default_account_id(%{account: account, accounts: accounts}) do
    if account && Account.takes_entries?(account) do
      account.id
    else
      case accounts
           |> Map.values()
           |> Enum.filter(&Account.takes_entries?/1)
           |> groups()
           |> AccountGroups.rows() do
        [%{account: first} | _rest] -> first.id
        [] -> nil
      end
    end
  end

  defp sides(nil), do: []
  defp sides(transaction), do: [transaction | transaction.subtransactions]

  @doc "Whether the transaction, one of its parts or a counterpart is reconciled."
  def locked?(transaction) do
    transaction
    |> sides()
    |> Enum.flat_map(&[&1, &1.transfer_transaction])
    |> Enum.any?(&match?(%Transaction{cleared: :reconciled, deleted_at: nil}, &1))
  end

  # Accounts the transaction uses, which stay selectable though closed or fed.
  defp kept_accounts(transaction, accounts) do
    sides(transaction)
    |> Enum.map(&(&1.payee && &1.payee.transfer_account_id))
    |> then(&[transaction && transaction.account_id | &1])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(Map.keys(accounts)))
  end

  @impl true
  def handle_event("change", %{"transaction" => changed} = event, socket) do
    params = TransactionForm.change(socket.assigns.params, changed, socket.assigns.accounts)
    {:noreply, socket |> after_change(params, event["_target"]) |> assign(:error, nil)}
  end

  def handle_event("pick", %{"side" => side, "field" => "payee", "value" => value}, socket) do
    %{params: params, accounts: accounts} = socket.assigns

    case value do
      "a:" <> id ->
        params = TransactionForm.pick_payee(params, side, {:transfer, id})
        category_id = params |> transfer_category(side, accounts) |> suggest_offered(socket)
        {:noreply, suggest(socket, params, side, category_id)}

      "p:" <> name ->
        params = TransactionForm.pick_payee(params, side, {:payee, String.trim(name)})
        {:noreply, suggest(socket, params, side, payee_category(socket, name))}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("pick", %{"side" => side, "field" => "category", "value" => id}, socket) do
    if TransactionForm.to_id(id) in CategoryOptions.ids(socket.assigns.categories) do
      params = TransactionForm.put_side(socket.assigns.params, side, %{"category_id" => id})

      {:noreply,
       assign(socket, params: params, suggested: MapSet.delete(socket.assigns.suggested, side))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("split", _params, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.split/1)}

  def handle_event("toggle_sign", _params, socket) do
    params = TransactionForm.toggle_sign(socket.assigns.params)
    {:noreply, directed(socket, params)}
  end

  def handle_event("add_subtransaction", _params, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.add_subtransaction/1)}

  def handle_event("remove_subtransaction", %{"index" => index}, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.remove_subtransaction(&1, index))}

  def handle_event("save", event, socket) do
    %{accounts: accounts, transaction: original} = socket.assigns
    params = TransactionForm.change(socket.assigns.params, event["transaction"] || %{}, accounts)

    with {:ok, attrs} <- TransactionForm.to_attrs(params, accounts, original),
         {:ok, _transaction} <- write(original, attrs, confirmed(event)) do
      {:noreply, done(socket, if(original, do: "Gespeichert.", else: "Gebucht."))}
    else
      {:error, error} -> {:noreply, assign(socket, params: params, error: error_message(error))}
    end
  end

  def handle_event("delete", event, socket) do
    case Ledger.delete_transaction(socket.assigns.transaction, confirmed(event)) do
      {:ok, _transaction} -> {:noreply, done(socket, "Buchung gelöscht.")}
      {:error, changeset} -> {:noreply, assign(socket, :error, error_message(changeset))}
    end
  end

  # A typed payee suggests its last category; one typed over a transfer is no transfer any more.
  defp after_change(socket, params, ["transaction", "payee"]),
    do: payee_typed(socket, params, @main)

  defp after_change(socket, params, ["transaction", "subtransactions", index, "payee"]),
    do: payee_typed(socket, params, index)

  defp after_change(socket, params, ["transaction", column]) when column in ["outflow", "inflow"],
    do: directed(socket, TransactionForm.keep_column(params, @main, column))

  defp after_change(socket, params, ["transaction", "subtransactions", index, column])
       when column in ["outflow", "inflow"],
       do: assign(socket, :params, TransactionForm.keep_column(params, index, column))

  defp after_change(socket, params, _target), do: assign(socket, :params, params)

  defp directed(socket, params) do
    params = TransactionForm.follow_direction(params, socket.assigns.ready_to_assign_id)
    suggested = socket.assigns.suggested

    suggested =
      if params["category_id"] == "", do: MapSet.delete(suggested, @main), else: suggested

    assign(socket, params: params, suggested: suggested)
  end

  defp payee_typed(socket, params, side) do
    old = TransactionForm.side(socket.assigns.params, side)
    new = TransactionForm.side(params, side)

    if {old["payee"], old["transfer_account_id"]} == {new["payee"], new["transfer_account_id"]},
      do: assign(socket, :params, params),
      else: suggest(socket, params, side, payee_category(socket, new["payee"] || ""))
  end

  defp suggest(socket, params, side, category_id) do
    suggested? = MapSet.member?(socket.assigns.suggested, side)
    {params, suggested} = TransactionForm.suggest(params, side, category_id, suggested?)
    set = if suggested, do: &MapSet.put/2, else: &MapSet.delete/2
    assign(socket, params: params, suggested: set.(socket.assigns.suggested, side))
  end

  defp payee_category(socket, name) do
    case Map.get(socket.assigns.payees_by_key, Names.lookup_key(name)) do
      %{last_category_id: id} -> offered(socket, id)
      nil -> nil
    end
  end

  defp transfer_category(params, side, accounts) do
    case TransactionForm.crossing(params, side, accounts) do
      {budget, tracking} ->
        Ledger.last_transfer_category_id(budget.id, tracking.transfer_payee.id)

      nil ->
        nil
    end
  end

  defp suggest_offered(nil, _socket), do: nil
  defp suggest_offered(id, socket), do: offered(socket, id)

  defp offered(socket, id), do: if(id in CategoryOptions.ids(socket.assigns.categories), do: id)

  defp write(nil, attrs, _opts), do: Ledger.create_transaction(attrs)
  defp write(original, attrs, opts), do: Ledger.update_transaction(original, attrs, opts)

  @doc "The Ledger's opts for an event: `reconciled: :confirmed` once the browser asked about a reconciled change."
  def confirmed(%{"reconciled" => "confirmed"}), do: [reconciled: :confirmed]
  def confirmed(_event), do: []

  defp done(socket, message) do
    send(self(), {__MODULE__, :done, message})
    socket
  end

  @doc "The errors of a transaction's changeset as one text, each with its field's label and a split's by part."
  def error_message(text) when is_binary(text), do: text
  def error_message(:not_a_proposal), do: "Der Zuordnungsvorschlag ist schon entschieden."

  def error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> messages(nil)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  # The split's subtransactions have errors of their own each, or the split has them as a whole.
  defp messages(errors, prefix) when is_map(errors) do
    Enum.flat_map(errors, fn
      {:subtransactions, parts} when is_list(parts) ->
        parts
        |> Enum.with_index(1)
        |> Enum.flat_map(fn
          {part, number} when is_map(part) -> messages(part, "Teil #{number}: ")
          {text, _number} -> ["Aufteilung: #{text}"]
        end)

      {field, texts} ->
        Enum.map(texts, &"#{prefix}#{Map.get(@labels, field, "Buchung")} #{&1}")
    end)
  end

  defp account_options(assigns) do
    assigns.accounts
    |> Map.values()
    |> Enum.filter(&(Account.takes_entries?(&1) or &1.id in assigns.kept_accounts))
    |> grouped()
  end

  # The other open accounts (and the closed ones the transaction uses), as the sidebar orders them.
  defp transfer_options(params, accounts) do
    own_id = TransactionForm.to_id(params["account_id"])

    used =
      [params | Enum.map(TransactionForm.subtransactions(params), &elem(&1, 1))]
      |> Enum.map(&TransactionForm.to_id(&1["transfer_account_id"]))

    accounts
    |> Map.values()
    |> Enum.filter(&((not &1.closed or &1.id in used) and &1.id != own_id))
    |> groups()
    |> AccountGroups.rows()
    |> Enum.map(& &1.account)
  end

  defp grouped(accounts) do
    for group <- groups(accounts),
        do: {group.label, Enum.map(group.rows, &{&1.account.name, &1.account.id})}
  end

  # The accounts grouped and ordered as in the sidebar.
  defp groups(accounts),
    do: accounts |> Enum.sort_by(&{&1.position, &1.id}) |> AccountGroups.build(%{})

  defp directed_remainder(params) do
    case TransactionForm.remainder(params) do
      nil -> nil
      left -> if params["sign"] == "+", do: left, else: -left
    end
  end

  defp sign_class("+"), do: "text-success"
  defp sign_class(_sign), do: "text-danger"

  defp sign_label("+"), do: "Eingang, umschalten auf Ausgang"
  defp sign_label(_sign), do: "Ausgang, umschalten auf Eingang"
end
