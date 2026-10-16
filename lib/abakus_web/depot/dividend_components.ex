defmodule AbakusWeb.Depot.DividendComponents do
  @moduledoc "How the screens show a dividend, see `Dividends.upcoming/4`."
  use Phoenix.Component

  use AbakusWeb, :verified_routes

  import Setzkasten.Components.Feedback, only: [badge: 1]

  alias AbakusWeb.Depot.Format

  attr :kind, :atom, required: true, values: [:announced, :forecast]
  attr :class, :any, default: nil

  @doc """
  Whether a dividend's date is fixed or estimated, as a status: the dot of an announced one in
  the colour of its bars, a forecast's neutral.
  """
  def kind_tag(assigns) do
    ~H"""
    <.badge tone={if @kind == :announced, do: :primary, else: :neutral} class={@class}>
      {kind_label(@kind)}
    </.badge>
    """
  end

  defp kind_label(:announced), do: "angekündigt"
  defp kind_label(:forecast), do: "Prognose"

  @doc "The `amount` (`:gross` or `:net`) of `dividend` in euros, with „~“ for a forecast."
  def expected(%{kind: :forecast} = dividend, amount, places),
    do: "~" <> Format.euros(dividend[amount], places)

  def expected(dividend, amount, places), do: Format.euros(dividend[amount], places)

  @doc "The total `amount` of `dividends` in euros, with „~“ as soon as a forecast counts."
  def expected_total(dividends, amount, places) do
    total = dividends |> Enum.sum_by(& &1[amount]) |> Format.euros(places)
    if Enum.any?(dividends, &(&1.kind == :forecast)), do: "~" <> total, else: total
  end

  attr :gross, :boolean, default: false, doc: "whether the amounts are before taxes"

  def forecast_note(assigns) do
    currencies = if assigns.gross, do: "Vor Steuern, Fremdwährungen", else: "Fremdwährungen"
    assigns = assign(assigns, currencies: currencies)

    ~H"""
    Angekündigt sind Termine von DivvyDiary. Die Prognose nimmt die Zahlungen der letzten
    12 Monate ein Jahr später, mal heutigem Bestand. {@currencies} zum letzten EZB‑Kurs.
    """
  end

  attr :security, :map, required: true, doc: "nil for a dividend booked without a security"
  attr :class, :any, default: nil

  def security_link(%{security: nil} = assigns) do
    ~H"""
    <span class={["font-medium text-base-content/70", @class]}>Ohne Wertpapier</span>
    """
  end

  def security_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/depot/securities/#{@security}"}
      class={["font-medium hover:underline", @class]}
    >
      {security_name(@security)}
    </.link>
    """
  end

  @doc "The page of a dividend's security, nil for one booked without a security."
  def security_path(nil), do: nil
  def security_path(security), do: ~p"/depot/securities/#{security}"

  @doc "A dividend's security by name, „Ohne Wertpapier“ for one booked without."
  def security_title(nil), do: "Ohne Wertpapier"
  def security_title(security), do: security_name(security)

  @doc "Names such as „All-World“ never break at their hyphen."
  def security_name(security), do: String.replace(security.name, "-", "‑")
end
