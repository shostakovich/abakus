defmodule AbakusWeb.Depot.TransactionsLive do
  @moduledoc """
  „Buchungen“: every transaction of the user, grouped by month and newest first, filtered by all,
  purchases and sales, earnings or account. A transaction booked in the Depot opens the dialog
  „Buchung bearbeiten“; those from the PP import are read-only.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{Portfolios, Valuation}
  alias Abakus.Depot.Portfolios.Transaction
  alias AbakusWeb.Depot.{Format, TransactionDialog}

  @filters [
    {nil, nil, "Alle"},
    {"trades", :trades, "Käufe und Verkäufe"},
    {"earnings", :earnings, "Erträge"},
    {"account", :account, "Konto"}
  ]

  @labels %{
    buy: "Kauf",
    sell: "Verkauf",
    inbound_delivery: "Einlieferung",
    outbound_delivery: "Auslieferung",
    security_transfer: "Depotwechsel",
    cash_transfer: "Umbuchung",
    deposit: "Einlage",
    removal: "Entnahme",
    dividend: "Dividende",
    interest: "Zinsen",
    interest_charge: "Zinsbelastung",
    tax: "Steuern",
    tax_refund: "Steuerrückerstattung",
    fee: "Gebühren",
    fee_refund: "Gebührenerstattung"
  }

  @inflows [:sell, :dividend, :interest, :deposit, :tax_refund, :fee_refund]
  @outflows [:buy, :removal, :interest_charge, :tax, :fee]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:transactions}
    >
      <.header>
        Buchungen
        <:subtitle>Aus Portfolio Performance importierte Buchungen sind nur lesbar.</:subtitle>
        <:actions>
          <.button
            id="transactions-book"
            variant={:primary}
            icon="plus"
            class="max-md:hidden"
            phx-click={TransactionDialog.open()}
          >
            Buchung erfassen
          </.button>
        </:actions>
      </.header>

      <section aria-label="Buchungen">
        <.tabs id="transaction-filter" label="Filter" class="mb-4">
          <:tab
            :for={{param, filter, label} <- @filters}
            patch={~p"/depot/transactions?#{filter_query(param)}"}
            active={@filter == filter}
          >
            {label}
          </:tab>
        </.tabs>

        <.empty_state
          :if={@months == [] and @filter != nil}
          id="transactions-empty"
          icon="list"
        >
          Keine Buchungen dieser Art.
        </.empty_state>

        <.empty_state
          :if={@months == [] and @filter == nil}
          id="transactions-empty"
          layout={:page}
          plush="receipt"
          icon="list"
          title="Noch keine Buchungen"
        >
          Erfasse deine erste Buchung, etwa eine Einlage oder einen Kauf.
          <:action>
            <.button variant={:primary} icon="plus" phx-click={TransactionDialog.open()}>
              Buchung erfassen
            </.button>
          </:action>
        </.empty_state>

        <.list :if={@months != []} id="transactions">
          <%= for {month, transactions} <- @months do %>
            <.list_heading>
              <h2 id={"month-#{Date.to_iso8601(month)}"}>{month_name(month)}</h2>
            </.list_heading>
            <.transaction
              :for={transaction <- transactions}
              transaction={transaction}
              month={month}
            />
          <% end %>
        </.list>
      </section>
    </Layouts.depot>
    """
  end

  attr :transaction, Transaction, required: true
  attr :month, Date, required: true

  defp transaction(assigns) do
    transaction = assigns.transaction

    assigns =
      assign(assigns,
        title: title(transaction),
        editable: Transaction.editable?(transaction)
      )

    ~H"""
    <.list_row
      id={"transaction-#{@transaction.id}"}
      title={@title}
      on_click={if @editable, do: TransactionDialog.edit(@transaction.id)}
      trailing_on_phone={:title}
      data-month={Date.to_iso8601(@month)}
    >
      <:leading><.avatar icon={type_icon(@transaction.type)} /></:leading>
      <span :if={@editable} class="sr-only"> bearbeiten</span>
      <:meta>{details(@transaction)}</:meta>
      <:trailing>
        <.amount
          value={signed_cents(@transaction)}
          currency={@transaction.currency}
          currency_display={Format.currency_display(@transaction.currency)}
          signed={signed?(@transaction.type)}
          tone={inflow?(@transaction.type)}
          class="font-semibold"
        />
      </:trailing>
    </.list_row>
    """
  end

  defp title(%Transaction{security: %{name: name}} = transaction),
    do: join_meta([@labels[transaction.type], name])

  defp title(transaction), do: @labels[transaction.type]

  defp type_icon(type) when type in [:dividend, :interest], do: "coins"

  defp type_icon(type)
       when type in [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer],
       do: "layers"

  defp type_icon(_type), do: "wallet"

  # From the user's money's view: what comes into an account counts plus, what leaves it minus;
  # deliveries and transfers move what is there already.
  defp signed_cents(%Transaction{type: type, amount: amount}) when type in @outflows, do: -amount
  defp signed_cents(%Transaction{amount: amount}), do: amount

  defp inflow?(type), do: type in @inflows
  defp signed?(type), do: type in @inflows or type in @outflows

  defp details(transaction) do
    join_meta(
      [Calendar.strftime(transaction.date_time, "%d.%m.%Y")] ++
        where(transaction) ++
        [
          shares(transaction),
          gross(transaction),
          unit(transaction, :fee, "Gebühren"),
          unit(transaction, :tax, "Steuern")
        ]
    )
  end

  defp where(%Transaction{type: :security_transfer} = transaction),
    do: ["#{portfolio(transaction.portfolio)} → #{portfolio(transaction.other_portfolio)}"]

  defp where(%Transaction{type: :cash_transfer} = transaction),
    do: ["#{name(transaction.account)} → #{name(transaction.other_account)}"]

  defp where(transaction) do
    [transaction.portfolio && Format.portfolio_name(transaction.portfolio)] ++
      [transaction.account && transaction.account.name]
  end

  defp portfolio(nil), do: "–"
  defp portfolio(portfolio), do: Format.portfolio_name(portfolio)

  defp name(nil), do: "–"
  defp name(record), do: record.name

  defp shares(%Transaction{shares: shares}) when shares in [nil, 0], do: nil

  defp shares(%Transaction{type: type} = transaction) when type in [:buy, :sell] do
    price = Valuation.price_per_share(transaction, transaction.currency)
    "#{Format.shares(transaction.shares)} Stück à #{Format.price(price, transaction.currency)}"
  end

  defp shares(transaction), do: "#{Format.shares(transaction.shares)} Stück"

  defp gross(%Transaction{type: :dividend, amount: amount} = transaction) do
    case Valuation.gross_value(transaction, transaction.currency) do
      ^amount -> nil
      gross -> "brutto #{money(gross, transaction)}"
    end
  end

  defp gross(_transaction), do: nil

  defp unit(transaction, type, label) do
    case unit_cents(transaction, type) do
      0 -> nil
      cents -> "#{label} #{money(cents, transaction)}"
    end
  end

  defp unit_cents(transaction, type),
    do: transaction.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount)

  defp money(cents, transaction),
    do: Format.amount(cents) <> "\u00A0" <> Format.currency(transaction.currency)

  defp month_name(month), do: "#{Format.month_name(month)} #{month.year}"

  defp filter_query(nil), do: []
  defp filter_query(param), do: [filter: param]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Buchungen",
       filters: @filters
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      Enum.find_value(@filters, fn {param, filter, _label} ->
        param == params["filter"] && filter
      end)

    {:noreply, socket |> assign(:filter, filter) |> load_transactions()}
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_transactions(socket)}

  defp load_transactions(socket) do
    scope = socket.assigns.current_scope
    assign(socket, :months, Portfolios.transactions_by_month(scope, socket.assigns.filter))
  end
end
