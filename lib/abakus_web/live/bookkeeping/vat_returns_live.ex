defmodule AbakusWeb.Bookkeeping.VatReturnsLive do
  @moduledoc """
  The Buchhaltung's „Umsatzsteuer“: the Voranmeldung of a quarter or the Umsatzsteuererklärung of a year
  (`Abakus.Bookkeeping.VatReturns`) under the form's Kennzahlen. `?period=2027-q1` or `?period=2027` picks it; without
  one it shows the quarter before today's, the one to file next.

  A quarter or year that is over is sent to ELSTER from here (`AbakusWeb.Bookkeeping.FilingPanel`).
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.Filings
  alias Abakus.{Format, LocalTime, Money}
  alias AbakusWeb.Bookkeeping.FilingPanel

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_vat}
    >
      <.header>
        Umsatzsteuer
        <:subtitle>
          {join_meta([
            Filings.title(@period),
            Format.date_span(@vat_return.first, @vat_return.last)
          ])}
        </:subtitle>
        <:actions>
          <div class="flex items-center gap-1">
            <.button
              id="vat-earlier"
              variant={:ghost}
              size={:sm}
              icon="chevron-left"
              icon_only
              label={"#{year(@period) - 1} anzeigen"}
              patch={path(shift(@period, -1))}
            />
            <.segmented
              id="vat-period"
              label="Zeitraum"
              size={:sm}
              value={param(@period)}
              options={
                for period <- periods(year(@period)),
                    do: %{
                      label: short_label(period),
                      long_label: long_label(period),
                      value: param(period),
                      path: path(period)
                    }
              }
            />
            <.button
              id="vat-later"
              variant={:ghost}
              size={:sm}
              icon="chevron-right"
              icon_only
              label={"#{year(@period) + 1} anzeigen"}
              patch={path(shift(@period, 1))}
            />
          </div>
        </:actions>
      </.header>
      <.table
        id="vat-lines"
        size={:sm}
        groups={[
          %{id: "vat-lines-taxes", label: nil, rows: @vat_return.lines},
          %{id: "vat-lines-totals", label: nil, rows: Enum.map(@vat_return.totals, &total_row/1)}
        ]}
        row_id={&"vat-#{&1.key}"}
        row_attrs={&if(&1[:total], do: %{class: "font-semibold"})}
      >
        <:col :let={line} label="Position">
          {line.label}
          <.cell_sub :if={kennzahlen(line) != []} hide_from={:sm}>
            Kz {Enum.join(kennzahlen(line), " · ")}
          </.cell_sub>
        </:col>
        <:col :let={line} label="Kz" show_from={:sm}>{line.base_kennzahl}</:col>
        <:col :let={line} label="Bemessungsgrundlage" align={:end}>
          <.amount :if={line.base} value={line.base * 100} decimals={0} />
        </:col>
        <:col :let={line} label="Kz" show_from={:sm}>{line.tax_kennzahl}</:col>
        <:col :let={line} label="Steuer" align={:end}><.amount value={line.tax} /></:col>
      </.table>
      <p class="mt-2 max-w-prose text-sm text-base-content/70">
        Nach vereinnahmten Entgelten: jede Buchung zählt an ihrem Datum, Umsatzsteuer wie Vorsteuer.
        Bemessungsgrundlagen in vollen Euro, abgerundet.
      </p>
      <.live_component
        module={FilingPanel}
        id="vat-filing-panel"
        prefix="vat"
        current_scope={@current_scope}
        period={@period}
        computed={@vat_return}
        summary={summary(@period, @vat_return)}
      />
    </Layouts.app>
    """
  end

  defp summary({:vat_year, _year} = period, vat_return),
    do:
      join_meta([
        Filings.title(period),
        "Abschlusszahlung / Erstattung #{Money.euros(vat_return.balance)}"
      ])

  defp summary(period, vat_return),
    do:
      join_meta([
        Filings.title(period),
        "Verbleibende Vorauszahlung #{Money.euros(vat_return.due)}"
      ])

  defp total_row(total),
    do: %{
      key: total.key,
      label: total.label,
      base_kennzahl: nil,
      base: nil,
      tax_kennzahl: total.kennzahl,
      tax: total.tax,
      total: true
    }

  defp kennzahlen(line), do: Enum.reject([line.base_kennzahl, line.tax_kennzahl], &is_nil/1)

  defp periods(year), do: Enum.map(1..4, &{:vat_quarter, year, &1}) ++ [{:vat_year, year}]

  defp year(period), do: elem(period, 1)

  defp shift({:vat_quarter, year, quarter}, by), do: {:vat_quarter, year + by, quarter}
  defp shift({:vat_year, year}, by), do: {:vat_year, year + by}

  defp long_label(period), do: "#{short_label(period)} #{year(period)}"

  defp short_label({:vat_year, _year}), do: "Jahr"
  defp short_label({:vat_quarter, _year, quarter}), do: "Q#{quarter}"

  defp path(period), do: ~p"/buchhaltung/vat?#{[period: param(period)]}"

  defp param({:vat_year, year}), do: "#{year}"
  defp param({:vat_quarter, year, quarter}), do: "#{year}-q#{quarter}"

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Umsatzsteuer")}

  @impl true
  def handle_params(params, _uri, socket) do
    period = parse(params["period"]) || last_quarter(LocalTime.today())
    vat_return = Filings.compute(socket.assigns.current_scope, period)
    {:noreply, assign(socket, period: period, vat_return: vat_return)}
  end

  @impl true
  def handle_info({FilingPanel, :sent, period}, socket),
    do: {:noreply, put_flash(socket, :info, "#{FilingPanel.noun(period)} an ELSTER gesendet.")}

  defp parse(param) when is_binary(param) do
    case Regex.run(~r/\A(\d{4})(?:-q([1-4]))?\z/, param) do
      [_all, year] -> {:vat_year, String.to_integer(year)}
      [_all, year, quarter] -> {:vat_quarter, String.to_integer(year), String.to_integer(quarter)}
      nil -> nil
    end
  end

  defp parse(_none), do: nil

  defp last_quarter(%Date{year: year, month: month}) when month <= 3,
    do: {:vat_quarter, year - 1, 4}

  defp last_quarter(%Date{year: year, month: month}), do: {:vat_quarter, year, div(month - 1, 3)}
end
