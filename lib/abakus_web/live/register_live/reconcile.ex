defmodule AbakusWeb.RegisterLive.Reconcile do
  @moduledoc """
  Reconciling one account in the register, as in YNAB. The popover asks whether the balance is right: with a bank
  balance it shows it with its date beside the cleared balance up to that date, without one it asks about the
  cleared balance. "Ja" reconciles. "Nein" asks for the bank's balance today; a differing bank balance offers that
  or to search the difference. Both lead to reconcile mode, whose bar shows the difference as the cleared state
  changes, until it is finished (with an adjustment for what is left) or cancelled.

  The bank's balance the account is reconciled against is kept as `Abakus.Ledger.reconcile/3` takes it, with its
  source: a stored bank balance counts up to its date, a balance entered by hand up to today.
  """
  use AbakusWeb, :html

  alias Abakus.Amount
  alias Abakus.Ledger.BankBalance
  alias Abakus.Money
  alias AbakusWeb.Format

  @doc "The bank's balance to reconcile against, from a stored bank balance."
  def bank(%BankBalance{} = bank),
    do: %{amount: bank.amount, date: bank.date, through: bank.date, source: bank.source}

  @doc "The bank's balance to reconcile against, entered by hand (or confirmed as it is) today."
  def bank(amount, %Date{} = today),
    do: %{amount: amount, date: today, through: today, source: :entered}

  @doc "Reads the balance typed into the popover."
  def entered(text, today) when is_binary(text) do
    with {:ok, amount} <- Money.parse(text, 2) do
      if Amount.valid?(amount),
        do: {:ok, bank(amount, today)},
        else: {:error, "Betrag " <> Amount.out_of_range_message()}
    end
  end

  def entered(_text, _today), do: {:error, "Betrag ist ungültig, etwa 1.234,56"}

  @doc "What the bank has more than the cleared balance; negative when it has less."
  def difference(%{bank: bank, cleared: cleared}), do: bank.amount - cleared

  def done_text(%{reconciled: count, adjustment: nil}), do: "Abgeglichen#{locked_text(count)}."

  def done_text(%{reconciled: count, adjustment: adjustment}),
    do:
      "Ausgleichsbuchung über #{Money.euros(adjustment.amount, signed: true)} angelegt#{locked_text(count)}."

  def refused_text(difference),
    do:
      "Nicht abgeglichen: Der Saldo weicht inzwischen um #{Money.euros(difference, signed: true)} ab."

  defp locked_text(0), do: ""
  defp locked_text(1), do: ", 1 Buchung abgeschlossen"
  defp locked_text(count), do: ", #{count} Buchungen abgeschlossen"

  attr :state, :map,
    default: nil,
    doc: "nil when closed, else `%{step: :ask | :enter, bank, cleared, error}`"

  @doc "The \"Abgleichen\" button with its popover."
  def editor(assigns) do
    ~H"""
    <.button
      id="reconcile-open"
      icon="lock"
      class="max-md:btn-square"
      aria-haspopup="dialog"
      aria-expanded={to_string(@state != nil)}
      phx-click={if @state, do: "reconcile_close", else: "reconcile_open"}
    >
      <span class="max-md:sr-only">Abgleichen</span>
    </.button>
    <.question :if={@state} state={@state} />
    """
  end

  attr :state, :map, required: true

  defp question(assigns) do
    ~H"""
    <.popover
      id="reconcile-menu"
      title="Konto abgleichen"
      anchor="reconcile-open"
      align={:end}
      show
      on_cancel={JS.push("reconcile_close")}
      class="w-80"
    >
      <.ask :if={@state.step == :ask} state={@state} difference={difference(@state)} />
      <.enter :if={@state.step == :enter} error={@state.error} />
    </.popover>
    """
  end

  attr :state, :map, required: true
  attr :difference, :integer, required: true

  defp ask(%{state: %{bank: %{source: :entered}}} = assigns) do
    ~H"""
    <p id="reconcile-question" class="pb-4 text-sm">
      Hat das Konto laut Bank <.amount value={@state.bank.amount} class="font-semibold" />?
    </p>
    <.answers yes />
    """
  end

  defp ask(assigns) do
    ~H"""
    <div class="text-sm">
      <div id="reconcile-bank" class="flex justify-between gap-3">
        <span>Banksaldo am {Format.date(@state.bank.date)}</span>
        <.amount value={@state.bank.amount} class="font-semibold" />
      </div>
      <p class="text-base-content/70">{source_label(@state.bank.source)}</p>
      <div id="reconcile-cleared" class="flex justify-between gap-3 pt-2">
        <span>Abgeglichener Saldo bis dahin</span>
        <.amount value={@state.cleared} class="font-semibold" />
      </div>
      <%= if @difference == 0 do %>
        <p id="reconcile-question" class="py-4">
          Hatte das Konto am {Format.date(@state.bank.date)}
          <.amount value={@state.bank.amount} class="font-semibold" />?
        </p>
      <% else %>
        <p id="reconcile-question" class="py-4">
          Differenz <.amount value={@difference} signed class="font-semibold" />.
          Fehlt eine Buchung oder ist eine nicht abgeglichen?
        </p>
      <% end %>
    </div>
    <.answers yes={@difference == 0} />
    """
  end

  attr :yes, :boolean,
    default: false,
    doc: "whether the balances agree, else the difference is to be searched"

  defp answers(assigns) do
    ~H"""
    <div class="flex gap-2 *:flex-1">
      <.button
        :if={@yes}
        id="reconcile-yes"
        size={:sm}
        variant={:primary}
        phx-click="reconcile_yes"
      >
        Ja
      </.button>
      <.button
        :if={!@yes}
        id="reconcile-search"
        size={:sm}
        variant={:primary}
        phx-click="reconcile_search"
      >
        Differenz suchen
      </.button>
      <.button id="reconcile-no" size={:sm} phx-click="reconcile_no">
        {if @yes, do: "Nein", else: "Anderer Saldo"}
      </.button>
    </div>
    """
  end

  attr :error, :string, default: nil

  defp enter(assigns) do
    ~H"""
    <form id="reconcile-form" phx-submit="reconcile_start" novalidate>
      <.input
        id="reconcile-balance"
        name="balance"
        value=""
        label="Wie viel hat das Konto heute laut Bank?"
        suffix="€"
        numeric
        autocomplete="off"
        required
        errors={List.wrap(@error)}
        phx-mounted={JS.focus()}
      />
      <.button type="submit" size={:sm} variant={:primary} class="mt-2 w-full">Weiter</.button>
    </form>
    """
  end

  defp source_label(:file), do: "laut Datei-Import"
  defp source_label(:bank), do: "laut Bank-Sync"

  attr :mode, :map, required: true, doc: "`%{bank, cleared}`"

  @doc """
  Reconcile mode, a bar that sticks under the toolbar: the bank's balance, the cleared balance and the difference,
  which follows the cleared state, with cancel and finish; finishing with a difference books an adjustment.
  """
  def bar(assigns) do
    assigns = assign(assigns, :difference, difference(assigns.mode))

    ~H"""
    <.alert
      id="reconcile-banner"
      aria-label="Abgleichen"
      tone={if @difference == 0, do: :success, else: :warning}
      class="sticky top-0 z-10 mb-3 py-2"
    >
      <dl class="flex flex-wrap items-baseline gap-x-6 gap-y-1">
        <div class="flex items-baseline gap-2">
          <dt class="text-base-content/70">Bankstand {as_of(@mode.bank)}</dt>
          <dd><.amount value={@mode.bank.amount} /></dd>
        </div>
        <div class="flex items-baseline gap-2">
          <dt class="text-base-content/70">Abgeglichen{through(@mode.bank)}</dt>
          <dd><.amount value={@mode.cleared} /></dd>
        </div>
        <div class="flex items-baseline gap-2">
          <dt class="text-base-content/70">Differenz</dt>
          <dd class="flex items-baseline gap-2">
            <.amount
              id="reconcile-difference"
              value={@difference}
              signed
              animate
              class="text-base font-semibold"
            />
            <span :if={@difference == 0}>Die Salden stimmen überein</span>
          </dd>
        </div>
      </dl>
      <:actions>
        <.button id="reconcile-cancel" size={:sm} phx-click="reconcile_cancel">Abbrechen</.button>
        <.button
          id="reconcile-finish"
          size={:sm}
          variant={:primary}
          phx-click="reconcile_finish"
          confirm={
            if @difference != 0,
              do: "Ausgleichsbuchung über #{Money.euros(@difference, signed: true)} anlegen?"
          }
          confirm_text="Sie gleicht die Differenz zur Bank aus. Danach ist das Konto abgeschlossen."
          confirm_label="Ausgleichen und abschließen"
        >
          {if @difference == 0, do: "Abschließen", else: "Ausgleichen und abschließen"}
        </.button>
      </:actions>
    </.alert>
    """
  end

  defp as_of(%{source: :entered}), do: "heute"
  defp as_of(%{date: date}), do: "am #{Format.date(date)}"

  defp through(%{source: :entered}), do: ""
  defp through(%{through: date}), do: " bis #{Format.date(date)}"
end
