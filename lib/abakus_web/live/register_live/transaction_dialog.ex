defmodule AbakusWeb.RegisterLive.TransactionDialog do
  @moduledoc """
  The transaction form, for a new transaction and for editing one alike: a modal on desktops, a sheet from the
  bottom on phones with the amount first. The form's state is `AbakusWeb.TransactionForm` params.

  A payee suggests its last category, and a suggestion goes again when the payee changes; a chosen category stays.
  A split's subtransactions each pick a category or an account. A transfer takes a category only between a budget
  and a tracking account. Changing or deleting a reconciled transaction, or one whose counterpart is, asks first.

  Tells its LiveView `{TransactionDialog, :done, message}` once the transaction is saved or deleted.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Categories, Ledger, Names}
  alias Abakus.Ledger.{Account, Transaction}
  alias AbakusWeb.{AccountGroups, CategoryOptions, Format, TransactionForm}

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
    transfer_subtransaction_id: "Buchung"
  }

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        form: to_form(assigns.params, as: :transaction),
        category?: TransactionForm.category?(assigns.params, assigns.accounts),
        own_account: own_account(assigns),
        subtransactions: TransactionForm.subtransactions(assigns.params)
      )

    ~H"""
    <div id={@id}>
      <div class="modal-backdrop show"></div>
      <div
        class="modal d-block app-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="tx-title"
        phx-window-keydown={JS.patch(@return_to)}
        phx-key="Escape"
      >
        <div class="modal-dialog modal-lg modal-dialog-scrollable app-sheet">
          <.form
            for={@form}
            id="transaction-form"
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
              <.link id="tx-close" patch={@return_to} class="btn-close" aria-label="Schließen"></.link>
            </div>
            <div class="modal-body">
              <div :if={@split_of} id="tx-split-of" class="alert alert-secondary small py-2">
                Teil einer Aufteilung in {@accounts[@transaction.account_id].name}; hier steht die ganze Aufteilung.
              </div>
              <div :if={@error} id="tx-error" class="alert alert-danger py-2" role="alert">
                {@error}
              </div>
              <div class="row g-3">
                <div class="col-sm-6 col-md-4 app-tx-late">
                  <label class="form-label" for="tx-account">Konto</label>
                  <select id="tx-account" name="transaction[account_id]" class="form-select">
                    {Phoenix.HTML.Form.options_for_select(
                      account_options(assigns),
                      @params["account_id"]
                    )}
                  </select>
                </div>
                <div class="col-sm-6 col-md-3 app-tx-late">
                  <label class="form-label" for="tx-date">Datum</label>
                  <input
                    id="tx-date"
                    type="date"
                    name="transaction[date]"
                    value={@params["date"]}
                    class="form-control"
                    required
                  />
                </div>
                <div class="col-md-5 app-tx-amount">
                  <label class="form-label" for="tx-amount">Betrag</label>
                  <div class="input-group">
                    <button
                      id="tx-sign"
                      type="button"
                      class={["btn btn-outline-secondary app-sign", sign_class(@params)]}
                      aria-label={sign_label(@params)}
                      title={sign_label(@params)}
                      phx-click="toggle_sign"
                      phx-target={@myself}
                    >
                      {if @params["sign"] == "+", do: "+", else: "−"}
                    </button>
                    <input type="hidden" name="transaction[sign]" value={@params["sign"]} />
                    <input
                      id="tx-amount"
                      name="transaction[amount]"
                      value={@params["amount"]}
                      class="form-control text-end app-q app-tx-amount-input"
                      inputmode="decimal"
                      placeholder="0,00"
                      autocomplete="off"
                      phx-debounce="300"
                    />
                    <span class="input-group-text">€</span>
                  </div>
                </div>
                <div class="col-12 app-tx-kind">
                  <div class="btn-group w-100" role="group" aria-label="Art">
                    <%= for {kind, label} <- [outflow: "Ausgabe", inflow: "Einnahme", transfer: "Umbuchung"] do %>
                      <input
                        id={"tx-kind-#{kind}"}
                        type="radio"
                        class="btn-check"
                        name="transaction[kind]"
                        value={kind}
                        checked={@params["kind"] == Atom.to_string(kind)}
                      />
                      <label class="btn btn-outline-secondary" for={"tx-kind-#{kind}"}>{label}</label>
                    <% end %>
                  </div>
                </div>
                <div :if={@params["kind"] != "transfer"} class="col-md-6">
                  <label class="form-label" for="tx-payee">Empfänger</label>
                  <input
                    id="tx-payee"
                    name="transaction[payee]"
                    value={@params["payee"]}
                    class="form-control"
                    list="tx-payees"
                    autocomplete="off"
                    placeholder="z. B. Frischmarkt"
                    phx-debounce="300"
                  />
                  <datalist id="tx-payees">
                    <option :for={payee <- @payees} value={payee.name}></option>
                  </datalist>
                </div>
                <div :if={@params["kind"] == "transfer"} class="col-md-6">
                  <label class="form-label" for="tx-other-account">
                    {if @params["sign"] == "+", do: "Von Konto", else: "Nach Konto"}
                  </label>
                  <select
                    id="tx-other-account"
                    name="transaction[other_account_id]"
                    class="form-select"
                  >
                    <option value="">Konto wählen …</option>
                    {Phoenix.HTML.Form.options_for_select(
                      transfer_options(assigns),
                      @params["other_account_id"]
                    )}
                  </select>
                </div>
                <div :if={@category?} class="col-md-6">
                  <label class="form-label" for="tx-category">Kategorie</label>
                  <select id="tx-category" name="transaction[category_id]" class="form-select">
                    <option value="">Kategorie wählen …</option>
                    {Phoenix.HTML.Form.options_for_select(@categories, @params["category_id"])}
                  </select>
                  <div :if={@suggested} id="tx-category-hint" class="form-text">
                    Zuletzt bei {@suggested_by} verwendet
                  </div>
                  <div :if={@params["kind"] == "transfer"} class="form-text">
                    Gilt für die Seite im Budgetkonto.
                  </div>
                </div>
                <div :if={@params["kind"] != "transfer"} class="col-12">
                  <div class="form-check form-switch">
                    <input type="hidden" name="transaction[split]" value="false" />
                    <input
                      id="tx-split"
                      type="checkbox"
                      role="switch"
                      class="form-check-input"
                      name="transaction[split]"
                      value="true"
                      checked={@params["split"] == "true"}
                    />
                    <label class="form-check-label" for="tx-split">Aufteilen</label>
                  </div>
                </div>
                <div :if={@params["kind"] != "transfer" and @params["split"] == "true"} class="col-12">
                  <.subtransaction
                    :for={{index, subtransaction} <- @subtransactions}
                    index={index}
                    subtransaction={subtransaction}
                    targets={subtransaction_targets(assigns)}
                    categories={@categories}
                    category?={
                      TransactionForm.subtransaction_category?(subtransaction, @params, @accounts)
                    }
                    note={@notes[subtransaction["id"]]}
                    removable={length(@subtransactions) > 2}
                    target={@myself}
                  />
                  <div class="d-flex align-items-center gap-2">
                    <button
                      id="tx-add-sub"
                      type="button"
                      class="btn btn-sm btn-outline-secondary d-inline-flex align-items-center gap-1"
                      phx-click="add_subtransaction"
                      phx-target={@myself}
                    >
                      <.icon name="plus" class="app-icon-sm" /> Teil hinzufügen
                    </button>
                    <.remainder amount={TransactionForm.remainder(@params)} />
                  </div>
                </div>
                <div class="col-12 app-tx-memo">
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
              <.link patch={@return_to} class="btn">Abbrechen</.link>
              <input :if={@locked} type="hidden" name="reconciled" value="confirmed" />
              <button
                id="tx-save"
                type="submit"
                class="btn btn-primary"
                phx-disable-with="Speichern …"
                data-confirm={@locked && "Diese Buchung ist abgeschlossen. Trotzdem ändern?"}
              >
                {if @transaction, do: "Speichern", else: "Buchen"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  attr :index, :string, required: true
  attr :subtransaction, :map, required: true
  attr :targets, :list, required: true
  attr :categories, :list, required: true
  attr :category?, :boolean, required: true
  attr :note, :string, default: nil
  attr :removable, :boolean, required: true
  attr :target, :any, required: true

  defp subtransaction(assigns) do
    assigns = assign(assigns, :name, "transaction[subtransactions][#{assigns.index}]")

    ~H"""
    <div id={"tx-sub-#{@index}"} class="d-flex align-items-start gap-2 mb-2">
      <input type="hidden" name={"#{@name}[id]"} value={@subtransaction["id"]} />
      <div class="flex-grow-1 app-min-w-0">
        <select
          id={"tx-sub-#{@index}-target"}
          name={"#{@name}[target]"}
          class="form-select form-select-sm"
          aria-label="Kategorie oder Konto"
        >
          <option value="">Nicht kategorisiert</option>
          {Phoenix.HTML.Form.options_for_select(@targets, @subtransaction["target"])}
        </select>
        <select
          :if={@category?}
          id={"tx-sub-#{@index}-category"}
          name={"#{@name}[category_id]"}
          class="form-select form-select-sm mt-1"
          aria-label="Kategorie im Budgetkonto"
        >
          <option value="">Kategorie wählen …</option>
          {Phoenix.HTML.Form.options_for_select(@categories, @subtransaction["category_id"])}
        </select>
        <div :if={@note} class="form-text mt-0 text-truncate">{@note}</div>
      </div>
      <div class="input-group input-group-sm app-tx-sub-amount">
        <input
          id={"tx-sub-#{@index}-amount"}
          name={"#{@name}[amount]"}
          value={@subtransaction["amount"]}
          class="form-control text-end app-q"
          inputmode="decimal"
          placeholder="0,00"
          aria-label="Betrag"
          autocomplete="off"
          phx-debounce="300"
        />
        <span class="input-group-text">€</span>
      </div>
      <button
        :if={@removable}
        id={"tx-sub-#{@index}-remove"}
        type="button"
        class="btn btn-sm btn-outline-secondary"
        aria-label="Teil entfernen"
        phx-click="remove_subtransaction"
        phx-value-index={@index}
        phx-target={@target}
      >
        ×
      </button>
    </div>
    """
  end

  attr :amount, :integer, default: nil

  defp remainder(assigns) do
    ~H"""
    <span id="tx-remainder" class="small ms-auto app-q">
      <%= cond do %>
        <% is_nil(@amount) -> %>
        <% @amount == 0 -> %>
          <span class="text-success">Aufteilung stimmt</span>
        <% true -> %>
          Noch aufzuteilen: <strong class={@amount < 0 && "app-neg"}>{Format.euros(@amount)}</strong>
      <% end %>
    </span>
    """
  end

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
      params: initial_params(socket.assigns),
      suggested: false,
      suggested_by: nil,
      error: nil,
      payees: payees,
      payees_by_key: Map.new(payees, &{&1.lookup_key, &1}),
      ready_to_assign_id: Categories.ready_to_assign!().id,
      categories: CategoryOptions.build(category_ids(transaction)),
      locked: locked?(transaction),
      notes: notes(transaction),
      kept_accounts: kept_accounts(transaction, accounts)
    )
  end

  defp initial_params(%{transaction: nil} = assigns),
    do: TransactionForm.new(default_account_id(assigns), assigns.today)

  defp initial_params(%{transaction: transaction}),
    do: TransactionForm.from_transaction(transaction)

  # The register's account if it takes manual entries, else the first that does, budget accounts first.
  defp default_account_id(%{account: account, accounts: accounts}) do
    if account && manual?(account) do
      account.id
    else
      case accounts
           |> Map.values()
           |> Enum.filter(&manual?/1)
           |> groups()
           |> AccountGroups.rows() do
        [%{account: first} | _rest] -> first.id
        [] -> nil
      end
    end
  end

  @doc "Whether manual entries go into the account: open and not fed by another app."
  def manual?(%Account{closed: closed, fed_by: fed_by}), do: not closed and is_nil(fed_by)

  defp sides(nil), do: []
  defp sides(transaction), do: [transaction | transaction.subtransactions]

  defp category_ids(transaction) do
    transaction
    |> sides()
    |> Enum.flat_map(
      &[&1.category_id, &1.transfer_transaction && &1.transfer_transaction.category_id]
    )
    |> Enum.reject(&is_nil/1)
  end

  defp locked?(transaction) do
    transaction
    |> sides()
    |> Enum.flat_map(&[&1, &1.transfer_transaction])
    |> Enum.any?(&match?(%Transaction{cleared: :reconciled, deleted_at: nil}, &1))
  end

  # What the form leaves as it is on an existing subtransaction: its payee (unless a transfer's) and memo.
  defp notes(transaction) do
    for subtransaction <- (transaction && transaction.subtransactions) || [],
        note = note(subtransaction),
        note != "",
        into: %{},
        do: {Integer.to_string(subtransaction.id), note}
  end

  defp note(subtransaction) do
    payee =
      if subtransaction.payee && is_nil(subtransaction.payee.transfer_account_id),
        do: subtransaction.payee.name

    [payee, subtransaction.memo] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")
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
    params = TransactionForm.change(socket.assigns.params, changed)
    {:noreply, socket |> after_change(params, event["_target"]) |> assign(:error, nil)}
  end

  def handle_event("toggle_sign", _params, socket) do
    params = TransactionForm.toggle_sign(socket.assigns.params)
    {:noreply, after_change(socket, params, ["transaction", "kind"])}
  end

  def handle_event("add_subtransaction", _params, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.add_subtransaction/1)}

  def handle_event("remove_subtransaction", %{"index" => index}, socket),
    do: {:noreply, update(socket, :params, &TransactionForm.remove_subtransaction(&1, index))}

  def handle_event("save", %{"transaction" => changed} = event, socket) do
    params = TransactionForm.change(socket.assigns.params, changed)
    %{accounts: accounts, transaction: original} = socket.assigns

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

  # A payee whose last category is not offered (hidden since) suggests nothing.
  defp after_change(socket, params, ["transaction", "payee"]) do
    payee =
      with %{last_category_id: id} = payee <-
             Map.get(socket.assigns.payees_by_key, Names.lookup_key(params["payee"] || "")),
           true <- id in CategoryOptions.ids(socket.assigns.categories) do
        payee
      else
        _not_offered -> nil
      end

    {params, suggested} = TransactionForm.suggest(params, payee, socket.assigns.suggested)
    assign(socket, params: params, suggested: suggested, suggested_by: payee && payee.name)
  end

  defp after_change(socket, params, ["transaction", "category_id"]),
    do: assign(socket, params: params, suggested: false)

  defp after_change(socket, params, ["transaction", "kind"]) do
    params = TransactionForm.kind_changed(params, socket.assigns.ready_to_assign_id)
    suggested = socket.assigns.suggested and params["category_id"] != ""
    assign(socket, params: params, suggested: suggested)
  end

  defp after_change(socket, params, _target), do: assign(socket, :params, params)

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

  defp own_account(assigns),
    do: Map.get(assigns.accounts, TransactionForm.to_id(assigns.params["account_id"]))

  defp account_options(assigns) do
    assigns.accounts
    |> Map.values()
    |> Enum.filter(&(manual?(&1) or &1.id in assigns.kept_accounts))
    |> grouped(& &1.name)
  end

  defp transfer_options(assigns, label \\ & &1.name, value \\ & &1.id) do
    own_id = assigns.own_account && assigns.own_account.id

    assigns.accounts
    |> Map.values()
    |> Enum.filter(&((not &1.closed or &1.id in assigns.kept_accounts) and &1.id != own_id))
    |> grouped(label, value)
  end

  # Categories for a budget account, then the other accounts as transfers.
  defp subtransaction_targets(assigns) do
    accounts = transfer_options(assigns, &"↔ #{&1.name}", &"a:#{&1.id}")

    categories =
      if is_nil(assigns.own_account) or Account.takes_category?(assigns.own_account),
        do: prefixed(assigns.categories),
        else: []

    categories ++ Enum.map(accounts, fn {group, options} -> {"↔ #{group}", options} end)
  end

  defp prefixed(options) do
    Enum.map(options, fn
      {group, categories} when is_list(categories) ->
        {group, Enum.map(categories, fn {name, id} -> {name, "c:#{id}"} end)}

      {name, id} ->
        {name, "c:#{id}"}
    end)
  end

  defp grouped(accounts, label, value \\ & &1.id) do
    for group <- groups(accounts),
        do: {group.label, Enum.map(group.rows, &{label.(&1.account), value.(&1.account)})}
  end

  # The accounts grouped and ordered as in the sidebar.
  defp groups(accounts),
    do: accounts |> Enum.sort_by(&{&1.position, &1.id}) |> AccountGroups.build(%{})

  defp sign_class(%{"sign" => "+"}), do: "text-success"
  defp sign_class(_params), do: "text-danger"

  defp sign_label(%{"kind" => "transfer", "sign" => "+"}), do: "Eingang, umschalten auf Ausgang"
  defp sign_label(%{"kind" => "transfer"}), do: "Ausgang, umschalten auf Eingang"
  defp sign_label(%{"sign" => "+"}), do: "Einnahme, umschalten auf Ausgabe"
  defp sign_label(_params), do: "Ausgabe, umschalten auf Einnahme"
end
