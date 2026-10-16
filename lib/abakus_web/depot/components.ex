defmodule AbakusWeb.Depot.Components do
  @moduledoc """
  The Depot's own pieces next to Setzkasten's components: figure tones, gains, the portfolio menu
  and URL ids.
  """
  use Phoenix.Component

  import Setzkasten.Components.Data, only: [amount: 1]
  import Setzkasten.Components.Icons, only: [icon: 1]
  import Setzkasten.Components.Navigation, only: [dropdown: 1]

  alias AbakusWeb.Depot.Format

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
