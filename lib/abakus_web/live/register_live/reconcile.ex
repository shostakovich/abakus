defmodule AbakusWeb.RegisterLive.Reconcile do
  @moduledoc """
  Reconciling one account in the register, as in YNAB. The popover asks whether the balance is right: with a bank
  balance it shows it with its date beside the cleared balance up to that date, without one it asks about the
  cleared balance. "Ja" reconciles. "Nein" asks for the bank's balance today; a differing bank balance offers that
  or to search the difference. Both lead to reconcile mode, whose banner shows the difference as the cleared state
  changes, until it is finished (with an adjustment for what is left) or cancelled.

  The bank's balance the account is reconciled against is kept as `Abakus.Ledger.reconcile/3` takes it, with its
  source: a stored bank balance counts up to its date, a balance entered by hand up to today.
  """
  use AbakusWeb, :html

  alias Abakus.Amount
  alias Abakus.Ledger.BankBalance
  alias AbakusWeb.Format

  @doc "The bank's balance to reconcile against, from a stored bank balance."
  def bank(%BankBalance{} = bank),
    do: %{amount: bank.amount, date: bank.date, through: bank.date, source: bank.source}

  @doc "The bank's balance to reconcile against, entered by hand (or confirmed as it is) today."
  def bank(amount, %Date{} = today),
    do: %{amount: amount, date: today, through: today, source: :entered}

  @doc "Reads the balance typed into the popover."
  def entered(text, today) when is_binary(text) do
    with false <- String.trim(text) == "",
         {:ok, amount} <- Format.parse_amount(text) do
      if Amount.valid?(amount),
        do: {:ok, bank(amount, today)},
        else: {:error, "Betrag " <> Amount.out_of_range_message()}
    else
      _blank_or_error -> {:error, "Betrag ist ungültig, etwa 1.234,56"}
    end
  end

  def entered(_text, _today), do: {:error, "Betrag ist ungültig, etwa 1.234,56"}

  @doc "What the bank has more than the cleared balance; negative when it has less."
  def difference(%{bank: bank, cleared: cleared}), do: bank.amount - cleared

  def done_text(%{reconciled: count, adjustment: nil}), do: "Abgeglichen#{locked_text(count)}."

  def done_text(%{reconciled: count, adjustment: adjustment}),
    do:
      "Ausgleichsbuchung über #{Format.signed_euros(adjustment.amount)} angelegt#{locked_text(count)}."

  def refused_text(difference),
    do: "Nicht abgeglichen: Der Saldo weicht inzwischen um #{Format.signed_euros(difference)} ab."

  defp locked_text(0), do: ""
  defp locked_text(1), do: ", 1 Buchung abgeschlossen"
  defp locked_text(count), do: ", #{count} Buchungen abgeschlossen"

  attr :state, :map,
    default: nil,
    doc: "nil when closed, else `%{step: :ask | :enter, bank, cleared, error}`"

  @doc "The \"Abgleichen\" button with its popover."
  def popover(assigns) do
    ~H"""
    <div class="dropdown" phx-click-away={@state && "reconcile_close"}>
      <button
        id="reconcile-open"
        type="button"
        class="btn btn-sm btn-primary"
        aria-expanded={to_string(@state != nil)}
        aria-controls="reconcile-menu"
        phx-click={if @state, do: "reconcile_close", else: "reconcile_open"}
      >
        Abgleichen
      </button>
      <div
        :if={@state}
        id="reconcile-menu"
        class="dropdown-menu dropdown-menu-end show p-3 app-reconcile-menu"
        data-bs-popper="static"
        role="dialog"
        aria-labelledby="reconcile-title"
        phx-window-keydown="reconcile_close"
        phx-key="Escape"
      >
        <div id="reconcile-title" class="fw-semibold mb-2">Konto abgleichen</div>
        <.ask :if={@state.step == :ask} state={@state} difference={difference(@state)} />
        <.enter :if={@state.step == :enter} error={@state.error} />
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :difference, :integer, required: true

  defp ask(%{state: %{bank: %{source: :entered}}} = assigns) do
    ~H"""
    <p id="reconcile-question" class="mb-3">
      Hat das Konto laut Bank <span class="app-q fw-semibold text-nowrap">{Format.euros(@state.bank.amount)}</span>?
    </p>
    <.answers yes />
    """
  end

  defp ask(assigns) do
    ~H"""
    <div id="reconcile-bank" class="d-flex justify-content-between gap-3">
      <span>Banksaldo am {Format.date(@state.bank.date)}</span>
      <span class="app-q fw-semibold text-nowrap">{Format.euros(@state.bank.amount)}</span>
    </div>
    <div class="small text-body-secondary mb-1">{source_label(@state.bank.source)}</div>
    <div id="reconcile-cleared" class="d-flex justify-content-between gap-3 mb-3">
      <span>Abgeglichener Saldo bis dahin</span>
      <span class="app-q fw-semibold text-nowrap">{Format.euros(@state.cleared)}</span>
    </div>
    <%= if @difference == 0 do %>
      <p id="reconcile-question" class="mb-3">
        Hatte das Konto am {Format.date(@state.bank.date)}
        <span class="app-q fw-semibold text-nowrap">{Format.euros(@state.bank.amount)}</span>?
      </p>
      <.answers yes />
    <% else %>
      <p id="reconcile-question" class="mb-3 text-danger">
        Differenz <span class="app-q fw-semibold text-nowrap">{Format.signed_euros(@difference)}</span>.
        Fehlt eine Buchung oder ist eine nicht abgeglichen?
      </p>
      <.answers />
    <% end %>
    """
  end

  attr :yes, :boolean,
    default: false,
    doc: "whether the balances agree, else the difference is to be searched"

  defp answers(assigns) do
    ~H"""
    <div class="d-flex gap-2">
      <button
        :if={@yes}
        id="reconcile-yes"
        type="button"
        class="btn btn-sm btn-primary flex-fill"
        phx-click="reconcile_yes"
      >
        Ja
      </button>
      <button
        :if={!@yes}
        id="reconcile-search"
        type="button"
        class="btn btn-sm btn-primary flex-fill"
        phx-click="reconcile_search"
      >
        Differenz suchen
      </button>
      <button
        id="reconcile-no"
        type="button"
        class="btn btn-sm btn-light flex-fill"
        phx-click="reconcile_no"
      >
        {if @yes, do: "Nein", else: "Anderer Saldo"}
      </button>
    </div>
    """
  end

  attr :error, :string, default: nil

  defp enter(assigns) do
    ~H"""
    <form id="reconcile-form" phx-submit="reconcile_start" novalidate>
      <label for="reconcile-balance" class="form-label">Wie viel hat das Konto heute laut Bank?</label>
      <div class="input-group input-group-sm">
        <input
          id="reconcile-balance"
          name="balance"
          type="text"
          inputmode="decimal"
          autocomplete="off"
          required
          class={["form-control text-end app-q", @error && "is-invalid"]}
          aria-describedby={@error && "reconcile-error"}
          phx-mounted={JS.focus()}
        />
        <span class="input-group-text">€</span>
      </div>
      <div :if={@error} id="reconcile-error" class="invalid-feedback d-block">{@error}</div>
      <button type="submit" class="btn btn-sm btn-primary w-100 mt-2">Weiter</button>
    </form>
    """
  end

  defp source_label(:file), do: "laut Datei-Import"
  defp source_label(:bank), do: "laut Bank-Sync"

  attr :mode, :map, required: true, doc: "`%{bank, cleared}`"

  @doc "Reconcile mode: the difference to the bank's balance, which follows the cleared state, with finish and cancel."
  def banner(assigns) do
    difference = difference(assigns.mode)
    assigns = assign(assigns, difference: difference, shown: Format.signed_euros(difference))

    ~H"""
    <div
      id="reconcile-banner"
      class={[
        "alert d-flex flex-wrap align-items-center gap-2 py-2 mb-3",
        if(@difference == 0, do: "alert-success", else: "alert-warning")
      ]}
      role="status"
    >
      <div class="me-auto">
        <div class="fw-semibold">
          Abgleichen mit dem Banksaldo von
          <span class="app-q text-nowrap">{Format.euros(@mode.bank.amount)}</span>
          {as_of(@mode.bank)}
        </div>
        <div class="small">
          Abgeglichener Saldo{through(@mode.bank)}: <span class="app-q text-nowrap">{Format.euros(@mode.cleared)}</span>.
          <%= if @difference == 0 do %>
            Die Salden stimmen überein.
          <% else %>
            Differenz <b id="reconcile-difference" class="app-q text-nowrap">{@shown}</b>.
            Markiere fehlende Buchungen als abgeglichen oder lege eine Ausgleichsbuchung an.
          <% end %>
        </div>
      </div>
      <button
        id="reconcile-cancel"
        type="button"
        class="btn btn-sm btn-light"
        phx-click="reconcile_cancel"
      >
        Abbrechen
      </button>
      <button
        id="reconcile-finish"
        type="button"
        class="btn btn-sm btn-primary"
        phx-click="reconcile_finish"
      >
        {if @difference == 0, do: "Abschließen", else: "Ausgleichsbuchung anlegen und abschließen"}
      </button>
    </div>
    """
  end

  defp as_of(%{source: :entered}), do: "heute"
  defp as_of(%{date: date}), do: "am #{Format.date(date)}"

  defp through(%{source: :entered}), do: ""
  defp through(%{through: date}), do: " bis #{Format.date(date)}"
end
