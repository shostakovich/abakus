defmodule AbakusWeb.Bookkeeping.VatReturnsLive do
  @moduledoc """
  The Buchhaltung's „Umsatzsteuer“: the Voranmeldung of a quarter or the Umsatzsteuererklärung of a year
  (`Abakus.Bookkeeping.VatReturns`) under the form's Kennzahlen. `?period=2027-q1` or `?period=2027` picks it; without
  one it shows the quarter before today's, the one to file next.

  A quarter that is over is sent to ELSTER from here (`Abakus.Bookkeeping.Filings`): the dialog asks for the PIN of
  the certificate at every send, or says what the settings still lack. A sent quarter shows when it was sent, its
  protocol, and a warning once its numbers no longer match those sent.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Elster, Filings, VatReturns}
  alias Abakus.{Format, LocalTime, Money}

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
          {join_meta([title(@period), Format.date_span(@vat_return.first, @vat_return.last)])}
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
      <div :if={@filing} class="mt-6 flex max-w-3xl flex-col gap-3">
        <.alert
          id="vat-filing"
          tone={:success}
          title={"Gesendet am #{Format.datetime(@filing.sent_at)}"}
        >
          {join_meta([
            Filings.locked_message(),
            @filing.transfer_ticket && "Transferticket #{@filing.transfer_ticket}"
          ])}
          <:actions>
            <.button
              id="vat-protocol"
              size={:sm}
              icon="download"
              href={~p"/buchhaltung/filings/#{@filing.id}/protocol"}
            >
              Übertragungsprotokoll
            </.button>
          </:actions>
        </.alert>
        <.alert
          :if={!Filings.matches?(@filing, @vat_return)}
          id="vat-filing-changed"
          tone={:warning}
          title="Die Zahlen weichen von der gesendeten Voranmeldung ab"
        >
          Seit dem Senden haben sich Buchungen des Quartals geändert. Eine berichtigte Voranmeldung geht bisher
          nur über „Mein ELSTER“.
        </.alert>
      </div>
      <.action_bar :if={sendable?(@period, @filing, @vat_return)} class="mt-6">
        <.button id="vat-send" variant={:primary} icon="send" phx-click="open_send">
          An ELSTER senden
        </.button>
      </.action_bar>
      <.modal
        :if={@sending}
        id="vat-send-modal"
        show
        title="An ELSTER senden"
        on_cancel={JS.push("close_send")}
      >
        <p class="mb-3 text-sm text-base-content/70">
          {join_meta([
            title(@period),
            "Verbleibende Vorauszahlung #{Money.euros(@vat_return.due)}"
          ])}
        </p>
        <.alert
          :if={@missing != []}
          id="vat-send-missing"
          tone={:warning}
          title="Noch nicht eingerichtet"
        >
          Es fehlt: {Enum.join(@missing, ", ")}.
          <:actions>
            <.button size={:sm} navigate={~p"/settings/buchhaltung/elster"}>Einstellungen</.button>
          </:actions>
        </.alert>
        <.form
          :if={@missing == []}
          for={%{}}
          id="vat-send-form"
          class="flex flex-col gap-3"
          phx-submit="send"
        >
          <.alert :if={Elster.test?()} id="vat-send-test" tone={:info}>
            Mit der Test-Hersteller-ID: ELSTER nimmt die Voranmeldung an, das Finanzamt verarbeitet sie nicht.
          </.alert>
          <.alert :if={@send_error} id="vat-send-error" tone={:error} title="Nicht gesendet">
            {@send_error}
          </.alert>
          <.input
            id="vat-send-pin"
            type="password"
            name="pin"
            value=""
            label="PIN des ELSTER-Zertifikats"
            autocomplete="off"
            help="Wird nur für dieses Senden gebraucht und nicht gespeichert."
          />
          <p class="max-w-prose text-sm text-base-content/70">
            Nach dem Senden ist das Quartal festgeschrieben.
          </p>
          <.action_bar>
            <.button id="vat-send-cancel" phx-click={hide_modal("vat-send-modal")}>
              Abbrechen
            </.button>
            <.button
              id="vat-send-submit"
              type="submit"
              variant={:primary}
              icon="send"
              loading={@submitting}
            >
              Senden
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp sendable?({_year, nil}, _filing, _vat_return), do: false
  defp sendable?(_period, filing, vat_return), do: filing == nil and Filings.over?(vat_return)

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

  defp periods(year), do: Enum.map(1..4, &{year, &1}) ++ [{year, nil}]

  defp year({year, _quarter}), do: year

  defp shift({year, quarter}, by), do: {year + by, quarter}

  defp title({year, nil}), do: "Umsatzsteuererklärung #{year}"
  defp title({year, quarter}), do: "Voranmeldung #{quarter}. Quartal #{year}"

  defp long_label({year, _quarter} = period), do: "#{short_label(period)} #{year}"

  defp short_label({_year, nil}), do: "Jahr"
  defp short_label({_year, quarter}), do: "Q#{quarter}"

  defp path(period), do: ~p"/buchhaltung/vat?#{[period: param(period)]}"

  defp param({year, nil}), do: "#{year}"
  defp param({year, quarter}), do: "#{year}-q#{quarter}"

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         page_title: "Umsatzsteuer",
         sending: false,
         submitting: false,
         send_error: nil,
         missing: []
       )}

  @impl true
  def handle_params(params, _uri, socket) do
    period = parse(params["period"]) || last_quarter(LocalTime.today())
    {:noreply, socket |> assign(period: period, sending: false) |> load()}
  end

  defp load(socket) do
    period = socket.assigns.period
    assign(socket, vat_return: compute(socket, period), filing: filing(socket, period))
  end

  defp filing(_socket, {_year, nil}), do: nil

  defp filing(socket, {year, quarter}),
    do: Filings.vat_quarter(socket.assigns.current_scope, year, quarter)

  @impl true
  def handle_event("open_send", _params, socket) do
    {:noreply,
     assign(socket,
       sending: true,
       send_error: nil,
       missing: Filings.missing(socket.assigns.current_scope)
     )}
  end

  def handle_event("close_send", _params, socket),
    do: {:noreply, assign(socket, sending: false)}

  def handle_event("send", %{"pin" => pin}, %{assigns: %{submitting: false}} = socket) do
    %{current_scope: scope, period: {year, quarter}} = socket.assigns

    {:noreply,
     socket
     |> assign(submitting: true, send_error: nil)
     |> start_async(:send, fn -> Filings.send_vat_quarter(scope, year, quarter, pin) end)}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:send, {:ok, {:ok, _filing}}, socket) do
    {:noreply,
     socket
     |> assign(submitting: false, sending: false)
     |> put_flash(:info, "Voranmeldung an ELSTER gesendet.")
     |> load()}
  end

  def handle_async(:send, {:ok, {:error, message}}, socket),
    do: {:noreply, assign(socket, submitting: false, send_error: message)}

  def handle_async(:send, {:exit, _reason}, socket),
    do:
      {:noreply,
       assign(socket,
         submitting: false,
         send_error: "Das Senden ist abgebrochen. Bitte noch einmal."
       )}

  defp parse(param) when is_binary(param) do
    case Regex.run(~r/\A(\d{4})(?:-q([1-4]))?\z/, param) do
      [_all, year] -> {String.to_integer(year), nil}
      [_all, year, quarter] -> {String.to_integer(year), String.to_integer(quarter)}
      nil -> nil
    end
  end

  defp parse(_none), do: nil

  defp last_quarter(%Date{year: year, month: month}) when month <= 3, do: {year - 1, 4}
  defp last_quarter(%Date{year: year, month: month}), do: {year, div(month - 1, 3)}

  defp compute(socket, {year, nil}), do: VatReturns.year(socket.assigns.current_scope, year)

  defp compute(socket, {year, quarter}),
    do: VatReturns.quarter(socket.assigns.current_scope, year, quarter)
end
