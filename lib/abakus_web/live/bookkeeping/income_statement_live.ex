defmodule AbakusWeb.Bookkeeping.IncomeStatementLive do
  @moduledoc """
  The Buchhaltung's „EÜR“: the Einnahmenüberschussrechnung of a year (`Abakus.Bookkeeping.IncomeStatements`) under
  the Kennzahlen of the Anlage EÜR, the income first, then the expenses and the totals. `?year=2027` picks it;
  without one it shows the year before today's, the one to file next.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.IncomeStatements
  alias Abakus.LocalTime

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_euer}
    >
      <.header>
        EÜR
        <:subtitle>Einnahmenüberschussrechnung {@year}</:subtitle>
        <:actions>
          <div class="flex items-center gap-1">
            <.button
              id="euer-earlier"
              variant={:ghost}
              size={:sm}
              icon="chevron-left"
              icon_only
              label={"#{@year - 1} anzeigen"}
              patch={path(@year - 1)}
            />
            <span id="euer-year" class="px-2 text-sm font-medium tabular-nums">{@year}</span>
            <.button
              id="euer-later"
              variant={:ghost}
              size={:sm}
              icon="chevron-right"
              icon_only
              label={"#{@year + 1} anzeigen"}
              patch={path(@year + 1)}
            />
          </div>
        </:actions>
      </.header>
      <.table
        id="euer-lines"
        size={:sm}
        groups={[
          %{id: "euer-lines-income", label: "Betriebseinnahmen", rows: @statement.income},
          %{id: "euer-lines-expenses", label: "Betriebsausgaben", rows: @statement.expenses},
          %{
            id: "euer-lines-totals",
            label: nil,
            rows: Enum.map(@statement.totals, &Map.put(&1, :total, true))
          }
        ]}
        row_id={&"euer-#{&1[:key] || &1.kennzahl}"}
        row_attrs={&if(&1[:total], do: %{class: "font-semibold"})}
      >
        <:col :let={line} label="Position">
          {line.label}
          <.cell_sub :if={line.kennzahl} hide_from={:sm}>Kz {line.kennzahl}</.cell_sub>
        </:col>
        <:col :let={line} label="Kz" show_from={:sm}>{line.kennzahl}</:col>
        <:col :let={line} label="Betrag" align={:end}><.amount value={line.amount} /></:col>
      </.table>
      <p class="mt-2 max-w-prose text-sm text-base-content/70">
        Nach Zufluss und Abfluss: jede Buchung zählt an ihrem Datum, ein Abgang an seinem. Käufe in
        Kategorien des Anlagevermögens zählen nur mit ihrer Vorsteuer, die Anschaffung über die Anlagen.
      </p>
    </Layouts.app>
    """
  end

  defp path(year), do: ~p"/buchhaltung/euer?#{[year: year]}"

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "EÜR")}

  @impl true
  def handle_params(params, _uri, socket) do
    year = parse(params["year"]) || LocalTime.today().year - 1

    {:noreply,
     assign(socket,
       year: year,
       statement: IncomeStatements.year(socket.assigns.current_scope, year)
     )}
  end

  defp parse(param) when is_binary(param) do
    case Integer.parse(param) do
      {year, ""} when year in 2000..2999 -> year
      _invalid -> nil
    end
  end

  defp parse(_none), do: nil
end
