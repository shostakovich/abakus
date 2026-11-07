defmodule AbakusWeb.Bookkeeping.FilingPanel do
  @moduledoc """
  Sending the return of `period` (`Abakus.Bookkeeping.Filings`) from the page that shows it, `computed`. A sent
  return shows when it was sent, its protocol, and a warning once its numbers no longer match those sent. One not
  sent yet offers „An ELSTER senden“ once its period is over: the dialog asks for the PIN of the certificate at every
  send, or says what the settings still lack. One filed before Abakus only shows that it is locked. `summary` names
  what the return comes to. Its ids start with `prefix`; it tells its LiveView `{FilingPanel, :sent, period}` once
  sent. The send runs apart from the LiveView and goes on when the page is closed.
  """
  use AbakusWeb, :live_component

  require Logger

  alias Abakus.Bookkeeping.{Elster, Filings}
  alias Abakus.Format

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div :if={@filing && @filing.filed_elsewhere} class="mt-6 max-w-3xl">
        <.alert id={"#{@prefix}-filing"} tone={:success} title="Vor Abakus abgegeben">
          {Filings.locked_message()}, seit dem Lexoffice-Import am {Format.datetime(@filing.sent_at)}.
        </.alert>
      </div>
      <div :if={@filing && !@filing.filed_elsewhere} class="mt-6 flex max-w-3xl flex-col gap-3">
        <.alert
          id={"#{@prefix}-filing"}
          tone={:success}
          title={"Gesendet am #{Format.datetime(@filing.sent_at)}"}
        >
          {join_meta([
            Filings.locked_message(),
            @filing.transfer_ticket && "Transferticket #{@filing.transfer_ticket}"
          ])}
          <:actions>
            <.button
              id={"#{@prefix}-protocol"}
              size={:sm}
              icon="download"
              href={~p"/buchhaltung/filings/#{@filing.id}/protocol"}
            >
              Übertragungsprotokoll
            </.button>
          </:actions>
        </.alert>
        <.alert
          :if={!Filings.matches?(@filing, @computed)}
          id={"#{@prefix}-filing-changed"}
          tone={:warning}
          title={"Die Zahlen weichen von der gesendeten #{noun(@period)} ab"}
        >
          Seit dem Senden haben sich Buchungen {of_period(@period)} geändert. Eine berichtigte {noun(
            @period
          )} geht bisher nur über „Mein ELSTER“.
        </.alert>
      </div>
      <.action_bar :if={!@filing and Filings.over?(@period)} class="mt-6">
        <.button
          id={"#{@prefix}-send"}
          variant={:primary}
          icon="send"
          phx-click="open_send"
          phx-target={@myself}
        >
          An ELSTER senden
        </.button>
      </.action_bar>
      <.modal
        :if={@sending}
        id={"#{@prefix}-send-modal"}
        show
        title="An ELSTER senden"
        on_cancel={JS.push("close_send", target: @myself)}
      >
        <p class="mb-3 text-sm text-base-content/70">{@summary}</p>
        <.alert
          :if={@missing != []}
          id={"#{@prefix}-send-missing"}
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
          id={"#{@prefix}-send-form"}
          class="flex flex-col gap-3"
          phx-submit="send"
          phx-target={@myself}
        >
          <.alert :if={Elster.test?()} id={"#{@prefix}-send-test"} tone={:info}>
            Mit der Test-Hersteller-ID: ELSTER nimmt die {noun(@period)} an, das Finanzamt verarbeitet sie
            nicht.
          </.alert>
          <.alert
            :if={@send_error}
            id={"#{@prefix}-send-error"}
            tone={:error}
            title="Nicht gesendet"
          >
            {@send_error}
          </.alert>
          <.input
            id={"#{@prefix}-send-pin"}
            type="password"
            name="pin"
            value=""
            label="PIN des ELSTER-Zertifikats"
            autocomplete="off"
            help="Wird nur für dieses Senden gebraucht und nicht gespeichert."
          />
          <p class="max-w-prose text-sm text-base-content/70">
            Nach dem Senden ist {the_period(@period)} festgeschrieben.
          </p>
          <.action_bar>
            <.button id={"#{@prefix}-send-cancel"} phx-click={hide_modal("#{@prefix}-send-modal")}>
              Abbrechen
            </.button>
            <.button
              id={"#{@prefix}-send-submit"}
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
    </div>
    """
  end

  @doc "What the return of `period` is called in a sentence: „Voranmeldung“, „Umsatzsteuererklärung“, „EÜR“."
  def noun({:vat_quarter, _year, _quarter}), do: "Voranmeldung"
  def noun({:vat_year, _year}), do: "Umsatzsteuererklärung"
  def noun({:euer, _year}), do: "EÜR"

  defp of_period({:vat_quarter, _year, _quarter}), do: "des Quartals"
  defp of_period(_year), do: "des Jahres"

  defp the_period({:vat_quarter, _year, _quarter}), do: "das Quartal"
  defp the_period(_year), do: "das Jahr"

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, sending: false, submitting: false, send_error: nil, missing: [])}

  @impl true
  def update(%{sent: {sent, result}}, socket) do
    %{current_scope: scope, period: period} = socket.assigns

    case result do
      {:ok, _filing} ->
        send(self(), {__MODULE__, :sent, sent})

        {:ok,
         assign(socket, submitting: false, sending: false, filing: Filings.sent(scope, period))}

      {:error, message} ->
        {:ok, assign(socket, submitting: false, send_error: message)}
    end
  end

  def update(assigns, socket) do
    socket =
      if assigns.period != socket.assigns[:period],
        do: assign(socket, sending: false, send_error: nil),
        else: socket

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:filing, Filings.sent(assigns.current_scope, assigns.period))}
  end

  @impl true
  def handle_event("open_send", _params, socket) do
    %{current_scope: scope, period: period} = socket.assigns

    {:noreply,
     assign(socket, sending: true, send_error: nil, missing: Filings.missing_for(scope, period))}
  end

  def handle_event("close_send", _params, socket),
    do: {:noreply, assign(socket, sending: false)}

  def handle_event("send", %{"pin" => pin}, %{assigns: %{submitting: false}} = socket) do
    %{current_scope: scope, period: period, myself: myself} = socket.assigns
    live_view = self()

    {:ok, _pid} =
      Task.Supervisor.start_child(Abakus.Bookkeeping.TaskSupervisor, fn ->
        send_update(live_view, myself, sent: {period, send_return(scope, period, pin)})
      end)

    {:noreply, assign(socket, submitting: true, send_error: nil)}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  defp send_return(scope, period, pin) do
    Filings.send_return(scope, period, pin)
  catch
    kind, reason ->
      Logger.error(Exception.format(kind, reason, __STACKTRACE__))
      {:error, "Das Senden ist abgebrochen. Bitte noch einmal."}
  end
end
