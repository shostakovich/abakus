defmodule AbakusWeb.Depot.AllocationComponents do
  @moduledoc """
  Bars of an allocation or a composition by region, sector or classification, each with its
  share, as the holdings screen and the security page show them under tabs.
  """
  use Phoenix.Component

  import Setzkasten.Components.Data, only: [bar: 1]
  import Setzkasten.Components.Feedback, only: [alert: 1]

  alias Abakus.Format

  @regions %{
    usa: "USA",
    canada: "Kanada",
    europe: "Europa",
    japan: "Japan",
    pacific_ex_japan: "Pazifik ohne Japan",
    emerging_markets: "Schwellenländer"
  }

  # DivvyDiary names the sectors by GICS, in English.
  @sectors %{
    "Information Technology" => "Technologie",
    "Financials" => "Finanzen",
    "Industrials" => "Industrie",
    "Health Care" => "Gesundheit",
    "Consumer Discretionary" => "Konsum zyklisch",
    "Consumer Staples" => "Basiskonsum",
    "Communication Services" => "Kommunikation",
    "Energy" => "Energie",
    "Materials" => "Grundstoffe",
    "Utilities" => "Versorger",
    "Real Estate" => "Immobilien"
  }

  attr :id, :string, required: true

  attr :rows, :list,
    required: true,
    doc: "each with its `key`, see `Allocation.of/2`, and `share`"

  @doc "A bar per region or sector, the largest at full width, „Ohne Angabe“ neutral."
  def composition_bars(assigns) do
    assigns = assign(assigns, :max, bar_max(Enum.map(assigns.rows, & &1.share)))

    ~H"""
    <ul id={@id} class="flex flex-col gap-3">
      <li :for={entry <- @rows}>
        <.bar
          label={label(entry.key)}
          value={bar_value(entry.share)}
          max={@max}
          show_value
          value_label={in_percent(entry.share)}
          tone={if is_nil(entry.key), do: :neutral, else: :primary}
        />
      </li>
    </ul>
    """
  end

  @doc "Why there are no regions and sectors: DivvyDiary has no API key."
  def missing_key(assigns) do
    ~H"""
    <.alert tone={:info}>
      Regionen und Sektoren brauchen einen DivvyDiary-API-Key (<code>DIVVYDIARY_API_KEY</code>).
    </.alert>
    """
  end

  @doc "A region, a sector as DivvyDiary names it, or nil for „Ohne Angabe“, in German."
  def label(nil), do: "Ohne Angabe"
  def label(region) when is_atom(region), do: Map.fetch!(@regions, region)
  def label(sector), do: Map.get(@sectors, sector, sector)

  @doc "A fraction in percent with one decimal place."
  def in_percent(fraction), do: fraction |> Decimal.mult(100) |> Format.percent()

  @doc """
  The bar's `max`: the largest of `fractions` in percent, so the largest fills the bar; 100 when
  there is none.
  """
  def bar_max(fractions) do
    case fractions |> Enum.map(&bar_value/1) |> Enum.max(fn -> 0.0 end) do
      max when max > 0 -> max
      _none -> 100.0
    end
  end

  @doc """
  A share or a target as the bar's `value` or `target`, in percent; odd targets such as −300 %
  or 400 % are kept within 0 and 100.
  """
  def bar_value(fraction),
    do: fraction |> within_bar() |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_float()

  defp within_bar(fraction), do: fraction |> Decimal.max(0) |> Decimal.min(1)
end
