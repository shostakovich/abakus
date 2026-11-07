defmodule AbakusWeb.LexofficeImportLive do
  @moduledoc """
  Import & Sync's Lexoffice, for the budget owner with the Buchhaltung: the one-off import of the customers,
  invoices and receipts from Lexoffice (`Abakus.Bookkeeping.LexofficeImport`) with an API key that is entered for
  the run and not stored, and the last Voranmeldung and the last year's returns filed, which it locks. It runs while
  the page is open, showing how far it is; run again, it brings only what is new. Below, the receipts waiting for
  review (`Abakus.Bookkeeping.LexofficeReceipts`), each attached to one of its proposals or dismissed from its menu;
  opening the page first attaches those that bank history imported since matches.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Filings, LexofficeImport, LexofficeReceipt, LexofficeReceipts}
  alias Abakus.{Format, LocalTime, Money, Paperless}
  alias AbakusWeb.{Areas, ImportSync, NotFoundError}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:import}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      account_dialog={@account_dialog}
    >
      <ImportSync.import_header
        tab={:lexoffice}
        current_scope={@current_scope}
        inbox={@depot_sidebar.inbox}
      >
        <:subtitle>
          Kunden, Rechnungen und Belege aus Lexoffice, mit den Original-Dateien in Paperless.
        </:subtitle>
      </ImportSync.import_header>
      <div class="flex max-w-prose flex-col gap-6">
        <.alert :if={!@paperless?} id="lexoffice-no-paperless" tone={:warning}>
          Die Dateien der Rechnungen und Belege gehen nach Paperless. Bitte erst <.link
            navigate={~p"/settings/paperless"}
            class="link"
          >Paperless verbinden</.link>.
        </.alert>
        <.form for={@form} id="lexoffice-form" phx-submit="import">
          <p class="pb-4 text-sm text-base-content/70">
            Abakus übernimmt alle Kunden und geschriebenen Rechnungen, ob bezahlt, offen oder storniert, und alle
            Belege mit ihren Zahlungen. Ein Beleg kommt an die Buchung des Geschäftskontos mit seinem Zahltag und
            Betrag; ist sie nicht eindeutig, steht er unten zur Prüfung. Ein zweiter Lauf bringt nur, was neu ist.
          </p>
          <.input
            field={@form[:token]}
            type="password"
            label="API-Schlüssel"
            value=""
            autocomplete="off"
            disabled={@running}
            help="In Lexoffice unter „Erweiterungen“ → „Public API“. Abakus speichert ihn nicht."
          />
          <.input
            field={@form[:quarter_filed]}
            type="select"
            label="Letzte abgegebene Voranmeldung"
            prompt="Bitte wählen"
            options={@quarter_options}
            disabled={@running}
            help="Auch eine des laufenden Jahres. Abakus schreibt die Quartale bis dahin nach dem Import fest."
          />
          <.input
            field={@form[:year_filed]}
            type="select"
            label="Jahreserklärungen abgegeben bis einschließlich"
            prompt="Bitte wählen"
            options={@year_options}
            disabled={@running}
            help="Die Umsatzsteuererklärung und die EÜR dieser Jahre sind beim Finanzamt; Abakus schreibt die Jahre nach dem Import fest."
          />
          <.action_bar class="mt-4">
            <.button
              id="lexoffice-submit"
              type="submit"
              variant={:primary}
              icon="download"
              loading={@running}
              disabled={!@paperless?}
            >
              Importieren
            </.button>
          </.action_bar>
        </.form>
        <.alert :if={@running} id="lexoffice-progress" busy title="Import läuft">
          {progress_text(@progress)} Bitte die Seite offen lassen; ein abgebrochener Import macht beim
          nächsten Mal weiter.
        </.alert>
        <.alert :if={@error} id="lexoffice-error" tone={:error} title="Import abgebrochen">
          {@error}
        </.alert>
        <.alert
          :if={@result}
          id="lexoffice-result"
          tone={if @result.skipped == [], do: :success, else: :warning}
          title="Import fertig"
        >
          {result_text(@result)}
          <ul :if={@result.skipped != []} id="lexoffice-skipped" class="mt-2 list-disc ps-5">
            <li :for={{number, reason} <- @result.skipped}>{skipped_text(number, reason)}</li>
          </ul>
        </.alert>
      </div>
      <section :if={@review != []} id="lexoffice-review" class="mt-8" aria-labelledby="review-title">
        <.section_heading id="review-title" count={length(@review)}>
          Belege zu prüfen
        </.section_heading>
        <p class="mb-3 max-w-prose text-sm text-base-content/70">
          Zu diesen Belegen gibt es keine eindeutige Buchung auf einem Geschäftskonto. Im Menü stehen die Buchungen
          mit dem Betrag einer Zahlung, bis eine Woche davor oder danach.
        </p>
        <.list id="review">
          <.list_row
            :for={{receipt, proposals} <- @review}
            id={"review-#{receipt.id}"}
            title={receipt.contact || LexofficeReceipt.title(receipt)}
            menu={:always}
            trailing_on_phone={:title}
          >
            <:meta>
              {join_meta([
                Format.date(receipt.date),
                receipt.number,
                payments_text(receipt),
                proposals_text(proposals)
              ])}
            </:meta>
            <:trailing><.amount value={receipt.total} signed tone /></:trailing>
            <:action
              :for={transaction <- proposals}
              id={"review-#{receipt.id}-attach-#{transaction.id}"}
              label={"Zuordnen: #{transaction_label(transaction)}"}
              icon="link"
              on_click={JS.push("attach", value: %{id: receipt.id, transaction: transaction.id})}
            />
            <:action
              :for={{paperless_id, index} <- Enum.with_index(receipt.paperless_ids)}
              id={"review-#{receipt.id}-file-#{index}"}
              label={if index == 0, do: "Beleg ansehen", else: "Datei #{index + 1} ansehen"}
              icon="file-text"
              href={~p"/buchhaltung/paperless/#{paperless_id}"}
            />
            <:action
              id={"review-#{receipt.id}-dismiss"}
              label="Keiner Buchung zuordnen"
              icon="x"
              confirm="Keiner Buchung zuordnen?"
              confirm_text="Der Beleg bleibt in Paperless und kommt von der Liste, etwa wenn er privat bezahlt ist."
              confirm_label="Nicht zuordnen"
              on_click={JS.push("dismiss", value: %{id: receipt.id})}
            />
          </.list_row>
        </.list>
      </section>
    </Layouts.app>
    """
  end

  defp payments_text(%{payments: []}), do: "ohne Zahlung"

  defp payments_text(%{payments: payments}),
    do:
      Enum.map_join(
        payments,
        ", ",
        &"bezahlt #{Format.date(&1.date)} #{Money.euros(abs(&1.amount))}"
      )

  defp proposals_text([]), do: "keine passende Buchung"
  defp proposals_text([_one]), do: "1 passende Buchung"
  defp proposals_text(proposals), do: "#{length(proposals)} passende Buchungen"

  defp transaction_label(%{payee: %{name: name}} = transaction),
    do: "#{Format.date(transaction.date)} · #{name} · #{Money.euros(transaction.amount)}"

  defp transaction_label(transaction),
    do: "#{Format.date(transaction.date)} · #{Money.euros(transaction.amount)}"

  defp progress_text(nil), do: "Kunden werden übernommen."

  defp progress_text({:customers, count}),
    do: "#{customers_text(count)} übernommen, die Rechnungen kommen."

  defp progress_text({:invoices, done, total}),
    do: "Rechnung #{Format.number(done)} von #{Format.number(total)}."

  defp progress_text({:receipts, done, total}),
    do: "Beleg #{Format.number(done)} von #{Format.number(total)}."

  defp result_text(result) do
    Enum.join(
      [
        "#{customers_text(result.customers)}, #{invoices_text(result.invoices)} und #{receipts_text(result.receipts)} übernommen.",
        matched_text(result)
        | locked_texts(result.locked)
      ]
      |> Enum.reject(&is_nil/1),
      " "
    )
  end

  defp matched_text(%{matched: 0, review: 0}), do: nil
  defp matched_text(%{matched: 0, review: review}), do: "#{receipts_text(review)} zu prüfen."

  defp matched_text(%{matched: matched, review: review}),
    do: "#{receipts_text(matched)} zugeordnet, #{Format.number(review)} zu prüfen."

  defp locked_texts(locked) do
    years = for {:euer, year} <- locked, do: year
    last_year = Enum.max(years, fn -> nil end)
    quarters = for {:vat_quarter, y, q} <- locked, last_year == nil or y > last_year, do: {y, q}
    [years_text(years), quarters_text(quarters)]
  end

  defp years_text([]), do: nil
  defp years_text([year]), do: "#{year} ist festgeschrieben."

  defp years_text(years),
    do: "#{Enum.min(years)} bis #{Enum.max(years)} sind festgeschrieben."

  defp quarters_text([]), do: nil

  defp quarters_text([{year, quarter}]),
    do: "Die #{Filings.title({:vat_quarter, year, quarter})} ist festgeschrieben."

  defp quarters_text(quarters) do
    {year, quarter} = Enum.max(quarters)
    "Die Voranmeldungen bis zum #{quarter}. Quartal #{year} sind festgeschrieben."
  end

  defp customers_text(1), do: "1 Kunde"
  defp customers_text(count), do: "#{Format.number(count)} Kunden"

  defp invoices_text(1), do: "1 Rechnung"
  defp invoices_text(count), do: "#{Format.number(count)} Rechnungen"

  defp receipts_text(1), do: "1 Beleg"
  defp receipts_text(count), do: "#{Format.number(count)} Belege"

  defp skipped_text(nil, reason), do: "Nicht übernommen: #{reason}"
  defp skipped_text(number, reason), do: "#{number} nicht übernommen: #{reason}"

  defp error_text(:running), do: "Ein Import aus Lexoffice läuft schon."
  defp error_text(:not_connected), do: "Paperless ist nicht verbunden."
  defp error_text(:unauthorized), do: "Lexoffice nimmt den API-Schlüssel nicht an."
  defp error_text(:rate_limited), do: "Lexoffice bremst gerade. Bitte später noch einmal."

  defp error_text(:consuming),
    do: "Paperless braucht zu lange für ein PDF. Bitte noch einmal starten."

  defp error_text(reason) when reason in [:timeout, :unreachable],
    do: "Lexoffice oder Paperless ist nicht erreichbar."

  defp error_text(_reason), do: "Lexoffice oder Paperless hat einen Fehler gemeldet."

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :bookkeeping) || raise NotFoundError
    LexofficeReceipts.match(scope)

    {:ok,
     socket
     |> assign(
       page_title: "Import & Sync",
       paperless?: Paperless.connected?(Paperless.get_connection(scope)),
       quarter_options: quarter_options(),
       year_options: year_options(),
       running: false,
       progress: nil,
       result: nil,
       error: nil
     )
     |> assign_form(%{
       "quarter_filed" => filed_value(Filings.filed_elsewhere_through(scope, :vat_quarter)),
       "year_filed" => filed_value(Filings.filed_elsewhere_through(scope, :euer))
     })
     |> load_review()}
  end

  defp quarter_options do
    year = LocalTime.today().year

    quarters =
      for y <- year..(year - 11)//-1,
          q <- 4..1//-1,
          Filings.over?({:vat_quarter, y, q}),
          do: {"#{q}. Quartal #{y}", "#{y}-#{q}"}

    [{"Noch keine", "none"} | quarters]
  end

  defp year_options do
    last = LocalTime.today().year - 1
    [{"Noch keine", "none"} | Enum.map(last..(last - 10)//-1, &{"#{&1}", "#{&1}"})]
  end

  defp filed_value(nil), do: ""
  defp filed_value({:vat_quarter, year, quarter}), do: "#{year}-#{quarter}"
  defp filed_value({:euer, year}), do: "#{year}"

  defp assign_form(socket, params) do
    params = Map.new(["quarter_filed", "year_filed"], &{&1, params[&1] || ""})
    assign(socket, :form, to_form(params, as: :lexoffice))
  end

  defp load_review(socket),
    do: assign(socket, :review, LexofficeReceipts.review(socket.assigns.current_scope))

  @impl true
  def handle_event(
        "import",
        %{"lexoffice" => %{"token" => token} = params},
        %{assigns: %{running: false}} = socket
      ) do
    socket = assign_form(socket, params)

    case {String.trim(token), quarter_filed(params["quarter_filed"]),
          year_filed(params["year_filed"])} do
      {"", _quarter, _year} ->
        {:noreply, assign(socket, error: "Bitte den API-Schlüssel eingeben.", result: nil)}

      {token, {:ok, quarter}, {:ok, year}} ->
        scope = socket.assigns.current_scope
        view = self()

        opts = [
          quarter_filed: quarter,
          year_filed: year,
          progress: &send(view, {:lexoffice_progress, &1})
        ]

        {:noreply,
         socket
         |> assign(running: true, progress: nil, result: nil, error: nil)
         |> start_async(:import, fn -> LexofficeImport.run(scope, fn -> token end, opts) end)}

      _unchosen ->
        {:noreply,
         assign(socket,
           error:
             "Bitte wählen, bis wann die Voranmeldungen und die Jahreserklärungen abgegeben sind.",
           result: nil
         )}
    end
  end

  def handle_event("import", _params, socket), do: {:noreply, socket}

  def handle_event("attach", %{"id" => id, "transaction" => transaction_id}, socket) do
    scope = socket.assigns.current_scope

    with %LexofficeReceipt{} = receipt <- LexofficeReceipts.get(scope, id),
         {:ok, receipt} <- LexofficeReceipts.attach(scope, receipt, transaction_id) do
      {:noreply,
       socket
       |> put_flash(:info, "#{LexofficeReceipt.title(receipt)} zugeordnet.")
       |> load_review()}
    else
      _error ->
        {:noreply,
         socket |> put_flash(:error, "Die Buchung passt nicht mehr zum Beleg.") |> load_review()}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case LexofficeReceipts.get(scope, id) do
      nil -> :ok
      receipt -> LexofficeReceipts.dismiss(scope, receipt)
    end

    {:noreply, load_review(socket)}
  end

  defp quarter_filed("none"), do: {:ok, nil}

  defp quarter_filed(value) when is_binary(value) do
    with [year, quarter] <- String.split(value, "-"),
         {year, ""} <- Integer.parse(year),
         {quarter, ""} when quarter in 1..4 <- Integer.parse(quarter) do
      {:ok, {year, quarter}}
    else
      _invalid -> :error
    end
  end

  defp quarter_filed(_none), do: :error

  defp year_filed("none"), do: {:ok, nil}

  defp year_filed(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} -> {:ok, year}
      _invalid -> :error
    end
  end

  defp year_filed(_none), do: :error

  @impl true
  def handle_info({:lexoffice_progress, progress}, socket),
    do: {:noreply, assign(socket, :progress, progress)}

  @impl true
  def handle_async(:import, {:ok, {:ok, result}}, socket),
    do: {:noreply, socket |> assign(running: false, result: result) |> load_review()}

  def handle_async(:import, {:ok, {:error, reason}}, socket),
    do: {:noreply, socket |> assign(running: false, error: error_text(reason)) |> load_review()}

  def handle_async(:import, {:exit, _reason}, socket),
    do: {:noreply, socket |> assign(running: false, error: error_text(:crashed)) |> load_review()}
end
