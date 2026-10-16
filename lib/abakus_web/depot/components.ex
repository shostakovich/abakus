defmodule AbakusWeb.Depot.Components do
  @moduledoc """
  The Depot's own pieces next to Setzkasten's components: the Depots pages' header and tabs, figure
  tones, gains, the portfolio menu and URL ids.
  """
  use Phoenix.Component
  use AbakusWeb, :verified_routes

  import Setzkasten.Components.Actions, only: [button: 1]
  import Setzkasten.Components.Data, only: [amount: 1]
  import Setzkasten.Components.Feedback, only: [badge: 1]
  import Setzkasten.Components.Icons, only: [icon: 1]
  import Setzkasten.Components.Layout, only: [header: 1]
  import Setzkasten.Components.Navigation, only: [dropdown: 1, tabs: 1]

  alias AbakusWeb.Depot.{Format, TransactionDialog}

  @tabs [
    holdings: "Bestand",
    transactions: "Buchungen",
    dividends: "Dividenden",
    performance: "Performance",
    securities: "Wertpapiere"
  ]

  attr :tab, :atom, required: true, values: Keyword.keys(@tabs)
  attr :portfolio, :any, default: nil, doc: "the one shown, nil for all"
  attr :portfolios, :list, default: [], doc: "those the menu offers; none on Wertpapiere"
  attr :inbox, :integer, default: 0, doc: "the recognised receipts in the inbox"

  attr :switch_path, :any,
    default: nil,
    doc: "the tab's page for a portfolio's id, if it keeps more than the portfolio"

  slot :subtitle
  slot :actions

  @doc """
  The Depots pages' title, all portfolios or one, with „Buchung erfassen“ and the portfolio menu,
  then the tabs: Bestand, Buchungen with the inbox's count, Dividenden, Performance, and
  Wertpapiere for all portfolios.
  """
  def depots_header(assigns) do
    assigns =
      assign(assigns,
        tabs: if(assigns.portfolio, do: Keyword.delete(@tabs, :securities), else: @tabs),
        portfolio_id: assigns.portfolio && assigns.portfolio.id
      )

    ~H"""
    <.header>
      {if @portfolio, do: Format.portfolio_name(@portfolio), else: "Depots"}
      <:subtitle :if={@subtitle != []}>{render_slot(@subtitle)}</:subtitle>
      <:actions>
        {render_slot(@actions)}
        <.portfolio_switcher
          :if={@tab != :securities}
          portfolios={@portfolios}
          portfolio={@portfolio}
          path={@switch_path || (&depots_path(@tab, &1))}
        />
        <.button
          id="depots-book"
          variant={:primary}
          icon="plus"
          class="max-md:hidden"
          phx-click={TransactionDialog.open()}
        >
          Buchung erfassen
        </.button>
      </:actions>
    </.header>
    <.tabs id="depots-tabs" label="Depots" class="mb-6">
      <:tab
        :for={{tab, label} <- @tabs}
        navigate={depots_path(tab, @portfolio_id)}
        active={tab == @tab}
      >
        {label}
        <.badge :if={tab == :transactions and @inbox > 0} id="inbox-count" style={:plain}>
          {@inbox}<span class="sr-only"> im Eingang</span>
        </.badge>
      </:tab>
    </.tabs>
    """
  end

  @doc "A tab of the Depots pages, of all portfolios or of the one with `portfolio_id`."
  def depots_path(tab, portfolio_id \\ nil)
  def depots_path(:holdings, id), do: ~p"/depot/holdings?#{portfolio_query(id)}"
  def depots_path(:transactions, id), do: ~p"/depot/transactions?#{portfolio_query(id)}"
  def depots_path(:dividends, id), do: ~p"/depot/dividends?#{portfolio_query(id)}"
  def depots_path(:performance, id), do: ~p"/depot/performance?#{portfolio_query(id)}"
  def depots_path(:securities, nil), do: ~p"/depot/securities"

  defp portfolio_query(nil), do: []
  defp portfolio_query(id), do: [portfolio: id]

  attr :portfolios, :list, required: true
  attr :portfolio, :any, required: true, doc: "the one shown, nil for all"
  attr :path, :any, required: true, doc: "the page for a portfolio's id, nil for all"

  @doc "A menu to show all portfolios or one."
  def portfolio_switcher(assigns) do
    ~H"""
    <.dropdown id="portfolio-menu" label="Depot" align={:end} trigger_class="btn-sm">
      <:trigger>
        <.icon name="briefcase" />{if @portfolio,
          do: Format.portfolio_name(@portfolio),
          else: "Gesamt"}
      </:trigger>
      <:item patch={@path.(nil)} active={!@portfolio}>Gesamt</:item>
      <:item
        :for={{portfolio, index} <- Enum.with_index(@portfolios)}
        patch={@path.(portfolio.id)}
        active={@portfolio && @portfolio.id == portfolio.id}
        divider={index == 0}
      >
        {Format.portfolio_name(portfolio)}
      </:item>
    </.dropdown>
    """
  end

  @doc "The class that mutes an amount of zero in a column of amounts."
  def muted(0), do: "text-base-content/70"
  def muted(_amount), do: nil

  @doc """
  The colour of a signed figure as `AbakusWeb.Depot.Format` shows it: green with a plus, red with
  a minus, muted for one that rounds to zero.
  """
  def tone(figure) do
    case sign(figure) do
      :success -> "text-success-ink"
      :error -> "text-error-ink"
      nil -> "text-base-content/70"
    end
  end

  attr :gain, :integer, required: true
  attr :purchase_value, :integer, default: 0, doc: "gives the gain in percent when positive"

  @doc "A gain in euros with its sign and colour, below it in percent of the purchase value."
  def gain(assigns) do
    ~H"""
    <.amount value={@gain} signed tone />
    <div :if={@purchase_value > 0} class={["text-sm", tone(Format.signed_euros(@gain, 2))]}>
      {@gain |> Format.percent_of(@purchase_value) |> Format.signed_percent(1)}
    </div>
    """
  end

  @doc "The `tone` of a signed figure for Setzkasten's `stat`: `:success`, `:error` or nil."
  def sign("+" <> _rest), do: :success
  def sign("−" <> _rest), do: :error
  def sign(_unsigned), do: nil

  @doc "A database id from a URL parameter; nil for anything else, beyond SQLite's integers too."
  def parse_id(param) do
    case Abakus.Schema.cast_id(param) do
      {:ok, id} -> id
      :error -> nil
    end
  end
end
