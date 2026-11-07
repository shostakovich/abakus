defmodule AbakusWeb.Bookkeeping.InboxLive do
  @moduledoc """
  The Buchhaltung's Posteingang: the business transactions still missing a category (`Abakus.Bookkeeping.inbox/1`),
  newest first. A row opens `TaxLineDialog`; once saved, the dialog moves on to the next transaction still open.
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
        <:subtitle>{count_text(length(@transactions))}</:subtitle>
      </.header>
      <.list :if={@transactions != []} id="inbox">
        <.list_row
          :for={transaction <- @transactions}
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
              transaction.memo
            ])}
          </:meta>
          <:trailing><.amount value={transaction.amount} signed tone /></:trailing>
        </.list_row>
      </.list>
      <.empty_state
        :if={@transactions == []}
        id="inbox-empty"
        layout={:page}
        plush="inbox"
        icon="inbox"
        title="Alles zugeordnet"
      >
        Jede Buchung der Geschäftskonten hat ihre Kategorie.
      </.empty_state>
      <.live_component
        :if={@dialog}
        module={TaxLineDialog}
        id="tax-lines"
        current_scope={@current_scope}
        transaction={@dialog}
        next={length(@transactions) > 1}
      />
    </Layouts.app>
    """
  end

  defp count_text(0), do: "Geschäftliche Buchungen, denen eine Kategorie fehlt."
  defp count_text(1), do: "1 geschäftliche Buchung ohne Kategorie."
  defp count_text(count), do: "#{count} geschäftliche Buchungen ohne Kategorie."

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
    do: assign(socket, :transactions, Bookkeeping.inbox(socket.assigns.current_scope))

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
    before = socket.assigns.transactions
    socket = load(socket)
    {:noreply, assign(socket, :dialog, next(socket, before, id))}
  end

  # The next one after the saved transaction that is still open, else the first one still open.
  defp next(socket, before, id) do
    open = MapSet.new(socket.assigns.transactions, & &1.id)
    later = before |> Enum.drop_while(&(&1.id != id)) |> Enum.drop(1)

    case Enum.find(later ++ before, &(&1.id != id and &1.id in open)) do
      nil -> nil
      transaction -> Enum.find(socket.assigns.transactions, &(&1.id == transaction.id))
    end
  end
end
