defmodule AbakusWeb.Depot.TransactionsLive do
  @moduledoc """
  „Buchungen“: every transaction of the user or of one portfolio, grouped by month and newest
  first, filtered by all, purchases and sales, earnings or account. Every transaction opens the
  dialog: „Buchung bearbeiten“ for a type the form knows, otherwise read-only, to delete it. A
  receipt opens as PDF.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{Portfolios, Valuation}
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.{Format, LocalTime, Money}
  alias AbakusWeb.Depot.Format, as: DepotFormat
  alias AbakusWeb.Depot.TransactionDialog

  @filters [
    {nil, nil, "Alle"},
    {"trades", :trades, "Käufe und Verkäufe"},
    {"earnings", :earnings, "Erträge"},
    {"account", :account, "Konto"}
  ]

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
      current={{:depots, @portfolio && @portfolio.id}}
    >
      <.depots_header
        tab={:transactions}
        portfolio={@portfolio}
        portfolios={@portfolios}
        switch_path={&transactions_path(@filter_param, &1)}
      />

      <section aria-label="Buchungen">
        <.tabs id="transaction-filter" label="Filter" class="mb-4">
          <:tab
            :for={{param, filter, label} <- @filters}
            patch={transactions_path(param, @portfolio && @portfolio.id)}
            active={@filter == filter}
          >
            {label}
          </:tab>
        </.tabs>

        <.empty_state
          :if={@months == [] and @filter != nil}
          id="transactions-empty"
          plush="clipboard-list"
          icon="list"
        >
          Keine Buchungen dieser Art.
        </.empty_state>

        <.empty_state
          :if={@months == [] and @filter == nil}
          id="transactions-empty"
          layout={:page}
          plush="clipboard-list"
          icon="list"
          title="Noch keine Buchungen"
        >
          Erfasse eine Buchung von Hand oder lade unter Import &amp; Sync den PDF-Beleg deiner Bank hoch.
          <:action>
            <.button variant={:primary} icon="plus" phx-click={TransactionDialog.open()}>
              Buchung erfassen
            </.button>
          </:action>
        </.empty_state>

        <.list :if={@months != []} id="transactions">
          <%= for {month, transactions} <- @months do %>
            <.list_heading>
              <h2 id={"month-#{Date.to_iso8601(month)}"}>{Format.month_year(month)}</h2>
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
      on_click={TransactionDialog.edit(@transaction.id)}
      trailing_on_phone={:title}
      data-month={Date.to_iso8601(@month)}
    >
      <:leading><.plush name={type_plush(@transaction.type)} size={:lg} /></:leading>
      <span class="sr-only">{if @editable, do: "bearbeiten", else: "ansehen"}</span>
      <:meta>{details(@transaction)}</:meta>
      <:trailing :let={place}>
        <.receipt_link :if={@transaction.receipt && place == :column} transaction={@transaction} />
        <.amount
          value={signed_cents(@transaction)}
          currency={@transaction.currency}
          currency_display={DepotFormat.currency_display(@transaction.currency)}
          signed={signed?(@transaction.type)}
          tone={inflow?(@transaction.type)}
          class="font-semibold"
        />
        <%!-- On phones the amount keeps the title line, the receipt goes below it. --%>
        <.receipt_link
          :if={@transaction.receipt && place == :title}
          transaction={@transaction}
          id_suffix="-phone"
        />
      </:trailing>
    </.list_row>
    """
  end

  attr :transaction, Transaction, required: true
  attr :id_suffix, :string, default: ""

  defp receipt_link(assigns) do
    ~H"""
    <a
      id={"transaction-#{@transaction.id}-receipt#{@id_suffix}"}
      href={~p"/depot/receipts/#{@transaction.receipt_id}"}
      target="_blank"
      rel="noopener"
      class={[
        "relative z-10 inline-flex items-center justify-center rounded-selector",
        "pointer-coarse:min-h-11 pointer-coarse:min-w-11"
      ]}
      aria-label={"Beleg #{@transaction.receipt.filename} öffnen"}
    >
      <.badge style={:plain} icon="file-text">PDF</.badge>
    </a>
    """
  end

  defp title(%Transaction{security: %{name: name}} = transaction),
    do: join_meta([DepotFormat.transaction_type(transaction.type), name])

  defp title(transaction), do: DepotFormat.transaction_type(transaction.type)

  defp type_plush(type) when type in [:dividend, :interest], do: "coins"

  defp type_plush(type)
       when type in [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer],
       do: "layers"

  defp type_plush(_type), do: "wallet"

  # From the user's money's view: what comes into an account counts plus, what leaves it minus;
  # deliveries and transfers move what is there already.
  defp signed_cents(%Transaction{type: type, amount: amount}) when type in @outflows, do: -amount
  defp signed_cents(%Transaction{amount: amount}), do: amount

  defp inflow?(type), do: type in @inflows
  defp signed?(type), do: type in @inflows or type in @outflows

  defp details(transaction) do
    join_meta(
      [Format.date(transaction.date_time)] ++
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
    [transaction.portfolio && DepotFormat.portfolio_name(transaction.portfolio)] ++
      [transaction.account && transaction.account.name]
  end

  defp portfolio(nil), do: "–"
  defp portfolio(portfolio), do: DepotFormat.portfolio_name(portfolio)

  defp name(nil), do: "–"
  defp name(record), do: record.name

  defp shares(%Transaction{shares: shares}) when shares in [nil, 0], do: nil

  defp shares(%Transaction{type: type} = transaction) when type in [:buy, :sell] do
    price = Valuation.price_per_share(transaction, transaction.currency)

    "#{DepotFormat.shares(transaction.shares)} Stück à #{DepotFormat.price(price, transaction.currency)}"
  end

  defp shares(transaction), do: "#{DepotFormat.shares(transaction.shares)} Stück"

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
    do: Money.amount(cents) <> "\u00A0" <> DepotFormat.currency(transaction.currency)

  defp transactions_path(filter_param, portfolio_id) do
    query = Enum.reject([filter: filter_param, portfolio: portfolio_id], &is_nil(elem(&1, 1)))
    ~p"/depot/transactions?#{query}"
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Buchungen", filters: @filters)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      Enum.find_value(@filters, fn {param, filter, _label} ->
        param == params["filter"] && filter
      end)

    portfolios = Portfolios.shown_portfolios(socket.assigns.current_scope, LocalTime.today())
    portfolio_id = parse_id(params["portfolio"])

    {:noreply,
     socket
     |> assign(
       filter: filter,
       filter_param: filter && params["filter"],
       portfolios: portfolios,
       portfolio: Enum.find(portfolios, &(&1.id == portfolio_id))
     )
     |> load_transactions()}
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_transactions(socket)}

  defp load_transactions(socket) do
    scope = socket.assigns.current_scope
    %{filter: filter, portfolio: portfolio} = socket.assigns
    assign(socket, :months, Portfolios.transactions_by_month(scope, filter, portfolio))
  end
end
