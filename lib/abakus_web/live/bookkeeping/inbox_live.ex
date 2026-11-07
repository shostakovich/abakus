defmodule AbakusWeb.Bookkeeping.InboxLive do
  @moduledoc """
  The Buchhaltung's Posteingang: the business transactions still missing a category or a receipt
  (`Abakus.Bookkeeping.inbox/1`), newest first, each saying what it misses. A row opens `TaxLineDialog` with the
  receipt beside it; once saved, the dialog moves on to the next transaction still open.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Bookkeeping, Format, Ledger}
  alias AbakusWeb.Bookkeeping.TaxLineDialog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_inbox}
    >
      <.header>
        Posteingang
        <:subtitle>{count_text(length(@entries))}</:subtitle>
      </.header>
      <.list :if={@entries != []} id="inbox">
        <.list_row
          :for={{transaction, missing} <- @entries}
          id={"inbox-#{transaction.id}"}
          on_click={JS.push("open", value: %{id: transaction.id})}
          selected={@dialog != nil and @dialog.id == transaction.id}
          trailing_on_phone={:title}
        >
          {title(transaction)}
          <:meta>
            {join_meta([
              Format.date(transaction.date),
              @accounts[transaction.account_id],
              transaction.subtransactions != [] && "Aufgeteilt",
              missing_text(missing),
              transaction.memo
            ])}
          </:meta>
          <:trailing><.amount value={transaction.amount} signed tone /></:trailing>
        </.list_row>
      </.list>
      <.empty_state
        :if={@entries == []}
        id="inbox-empty"
        layout={:page}
        plush="inbox"
        icon="inbox"
        title="Alles zugeordnet"
      >
        Jede Buchung der Geschäftskonten hat ihre Kategorie und ihren Beleg.
      </.empty_state>
      <.live_component
        :if={@dialog}
        module={TaxLineDialog}
        id="tax-lines"
        current_scope={@current_scope}
        transaction={@dialog}
        next={length(@entries) > 1}
      />
    </Layouts.app>
    """
  end

  defp count_text(0), do: "Geschäftliche Buchungen, denen eine Kategorie oder ein Beleg fehlt."
  defp count_text(1), do: "1 geschäftliche Buchung ohne Kategorie oder Beleg."
  defp count_text(count), do: "#{count} geschäftliche Buchungen ohne Kategorie oder Beleg."

  defp missing_text([:category, :receipt]), do: "Kategorie und Beleg fehlen"
  defp missing_text([:category]), do: "Kategorie fehlt"
  defp missing_text([:receipt]), do: "Beleg fehlt"

  defp title(%{payee: %{name: name}}), do: name
  defp title(_transaction), do: "Ohne Empfänger"

  @impl true
  def mount(_params, _session, socket) do
    accounts = Map.new(Ledger.list_accounts(socket.assigns.current_scope), &{&1.id, &1.name})

    {:ok,
     socket
     |> assign(page_title: "Posteingang", accounts: accounts, dialog: nil)
     |> load()}
  end

  defp load(socket),
    do: assign(socket, :entries, Bookkeeping.inbox(socket.assigns.current_scope))

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    case Bookkeeping.get_transaction(socket.assigns.current_scope, id) do
      nil -> {:noreply, socket |> put_flash(:error, "Buchung nicht gefunden.") |> load()}
      transaction -> {:noreply, assign(socket, :dialog, transaction)}
    end
  end

  def handle_event("close_tax_lines", _params, socket),
    do: {:noreply, socket |> assign(:dialog, nil) |> load()}

  @impl true
  def handle_info({TaxLineDialog, :done, id}, socket) do
    before = transactions(socket)
    socket = load(socket)
    {:noreply, assign(socket, :dialog, next(transactions(socket), before, id))}
  end

  defp transactions(socket), do: Enum.map(socket.assigns.entries, &elem(&1, 0))

  # The next one after the saved transaction that is still open, else the first one still open.
  defp next(open, before, id) do
    open_ids = MapSet.new(open, & &1.id)
    later = before |> Enum.drop_while(&(&1.id != id)) |> Enum.drop(1)

    case Enum.find(later ++ before, &(&1.id != id and &1.id in open_ids)) do
      nil -> nil
      transaction -> Enum.find(open, &(&1.id == transaction.id))
    end
  end
end
