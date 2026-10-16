defmodule AbakusWeb.Depot.SecuritiesLive do
  use AbakusWeb, :depot_live_view

  import Ecto.Changeset, only: [change: 1]

  alias Abakus.Depot.{ExchangeRates, MarketData, Securities, Settings}
  alias AbakusWeb.Depot.Format

  @feeds [{"Yahoo", "yahoo"}, {"Portfolio Performance", "manual"}]

  # What a new security from Yahoo starts with: the MSCI ACWI, in euros on Xetra.
  @symbol "IUSQ.DE"

  @unknown_benchmark "Dieses Wertpapier gibt es nicht mehr, die Benchmark bleibt."

  @symbol_help "Wird deine Benchmark. Name, Währung und Kurse kommen von Yahoo; ein " <>
                 "vorhandenes Symbol wird übernommen statt doppelt angelegt."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :symbol_help, @symbol_help)

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={{:depots, nil}}
    >
      <.depots_header tab={:securities}>
        <:subtitle>
          Kurse kommen von Yahoo, täglich um 18:00 und beim Öffnen dieser Seite. Am selben Tag gilt
          ein Kurs aus Portfolio Performance vor einem von Yahoo.
        </:subtitle>
      </.depots_header>

      <div class="flex flex-col gap-8">
        <section id="benchmark" aria-labelledby="benchmark-title">
          <.section_heading id="benchmark-title">Benchmark</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Vermögen und Performance vergleichen deine Depots mit diesem Wertpapier, wenn du dort „Benchmark“ einschaltest.
          </p>
          <div class="grid gap-x-12 gap-y-4 lg:grid-cols-2">
            <.form
              for={@benchmark_form}
              id="benchmark-form"
              phx-change="save_benchmark"
              phx-submit="save_benchmark"
            >
              <.input
                field={@benchmark_form[:benchmark_id]}
                type="select"
                label="Wertpapier"
                options={benchmark_options(@active, @benchmark)}
                help="Gilt sofort, ohne Speichern."
              />
            </.form>
            <.form for={@symbol_form} id="yahoo-security" phx-submit="create_security">
              <h3 class="fieldset-legend text-xs">Oder neu per Yahoo-Symbol anlegen</h3>
              <.input
                field={@symbol_form[:symbol]}
                label="Yahoo-Symbol"
                inline
                spellcheck="false"
                autocapitalize="characters"
                help={@symbol_help}
              >
                <.button type="submit" class="join-item" phx-disable-with="Wird abgerufen …">
                  Anlegen
                </.button>
              </.input>
            </.form>
          </div>
        </section>

        <section id="exchange-rates" aria-labelledby="exchange-rates-title">
          <.section_heading id="exchange-rates-title">Wechselkurse</.section_heading>
          <p class="max-w-prose text-sm">
            <%= if @rates_until do %>
              EZB-Referenzkurse bis {Format.date(@rates_until)}, täglich um 18:00 aktualisiert.
            <% else %>
              Noch keine Wechselkurse; sie kommen mit dem nächsten Abruf um 18:00.
            <% end %>
          </p>
          <p
            :if={@last_run && @last_run.error}
            class="mt-2 flex items-center gap-1.5 text-sm text-error-ink"
          >
            <.icon name="circle-alert" class="shrink-0" />{@last_run.error}
          </p>
        </section>

        <section id="active-securities" aria-labelledby="active-securities-title">
          <.section_heading id="active-securities-title" count={length(@active)}>
            Aktive Wertpapiere
          </.section_heading>
          <.empty_state :if={@active == []} plush="layers" icon="layers">
            Noch keine Wertpapiere. Lege eines beim Erfassen einer Buchung per ISIN an oder übernimm
            sie aus Portfolio Performance.
            <:action>
              <.button href={~p"/depot/import"} icon="upload">PP-Datei importieren</.button>
            </:action>
          </.empty_state>
          <.list :if={@active != []}>
            <.security
              :for={security <- @active}
              security={security}
              benchmark={@benchmark == security}
              feed_form={@feed_forms[security.id]}
            />
          </.list>
        </section>

        <.disclosure
          :if={@retired != []}
          id="retired"
          summary="Ausgemustert"
          count={length(@retired)}
        >
          <.list flush>
            <.security
              :for={security <- @retired}
              security={security}
              benchmark={@benchmark == security}
              feed_form={@feed_forms[security.id]}
            />
          </.list>
        </.disclosure>
      </div>
    </Layouts.depot>
    """
  end

  attr :security, :map, required: true
  attr :benchmark, :boolean, default: false
  attr :feed_form, Phoenix.HTML.Form, required: true

  defp security(assigns) do
    ~H"""
    <li class="list-row" id={"security-#{@security.id}"}>
      <div class="list-col-grow min-w-0">
        <div class="flex items-start gap-4">
          <div class="min-w-0 grow">
            <p class="flex flex-wrap items-center gap-2 font-medium wrap-anywhere">
              {@security.name}
              <.badge :if={@benchmark} style={:plain}>Benchmark</.badge>
            </p>
            <p class="text-sm text-base-content/70">
              {join_meta([@security.isin, @security.currency])}
            </p>
          </div>
          <div class="shrink-0 text-end">
            <p class="tabular-nums whitespace-nowrap">
              {Format.price(@security.latest_close, @security.currency)}
            </p>
            <p class="text-sm text-base-content/70 whitespace-nowrap">{quote_time(@security)}</p>
          </div>
        </div>

        <p :if={@security.fetch_error} class="mt-2 flex items-center gap-1.5 text-sm text-error-ink">
          <.icon name="circle-alert" class="shrink-0" />{@security.fetch_error}
        </p>
        <p
          :if={!@security.fetch_error && @security.fetched_at}
          class="mt-2 text-sm text-base-content/70"
        >
          Zuletzt abgerufen {Format.datetime(@security.fetched_at)}
        </p>

        <.form
          for={@feed_form}
          id={"feed-#{@security.id}"}
          phx-submit="save_feed"
          class="mt-2 grid items-end gap-x-4 sm:grid-cols-[1fr_1fr_auto]"
        >
          <input type="hidden" name="security_id" value={@security.id} />
          <.input
            field={@feed_form[:quote_feed]}
            type="select"
            label="Kursquelle"
            options={feeds()}
          />
          <.input
            field={@feed_form[:symbol]}
            label="Yahoo-Symbol"
            placeholder="z. B. VGWL.DE"
            spellcheck="false"
          />
          <div class="py-1">
            <.button
              id={"feed-#{@security.id}-save"}
              type="submit"
              class="max-sm:w-full"
              saved
              phx-disable-with="Speichert …"
            >
              Speichern
            </.button>
          </div>
        </.form>
      </div>
    </li>
    """
  end

  defp feeds, do: @feeds

  # The active securities, and the benchmark even once it is retired.
  defp benchmark_options(active, benchmark) do
    securities = if benchmark in [nil | active], do: active, else: active ++ [benchmark]
    [{"Keine Benchmark", ""} | Enum.map(securities, &{&1.name, &1.id})]
  end

  defp quote_time(%{latest_at: %DateTime{} = at}), do: "Stand " <> Format.datetime(at)
  defp quote_time(%{latest_date: %Date{} = date}), do: "Stand " <> Format.date(date)
  defp quote_time(_security), do: "noch kein Kurs"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Wertpapiere")
     |> assign(:symbol_form, symbol_form())
     |> load()}
  end

  defp symbol_form(changeset \\ Securities.change_yahoo_symbol(%{"symbol" => @symbol})),
    do: to_form(changeset, as: :yahoo)

  # Loads the data and resets every form.
  defp load(socket) do
    socket
    |> assign(feed_forms: %{})
    |> reload()
  end

  # Loads the data and keeps the forms, so an update in the background spares what is typed.
  defp reload(socket) do
    scope = socket.assigns.current_scope
    {retired, active} = scope |> Securities.list_securities() |> Enum.split_with(& &1.retired)
    securities = active ++ retired

    benchmark_id = Settings.benchmark_id(scope)
    benchmark = Enum.find(securities, &(&1.id == benchmark_id))

    socket
    |> assign(active: active, retired: retired, securities: Map.new(securities, &{&1.id, &1}))
    |> assign(
      benchmark: benchmark,
      benchmark_form: to_form(%{"benchmark_id" => benchmark && benchmark.id}, as: :benchmark)
    )
    |> update(:feed_forms, &add_missing(&1, securities, fn s -> feed_form(s, change(s)) end))
    |> assign(rates_until: ExchangeRates.last_date(), last_run: MarketData.last_run())
  end

  defp add_missing(forms, securities, new_form),
    do: Map.new(securities, &{&1.id, Map.get_lazy(forms, &1.id, fn -> new_form.(&1) end)})

  # Field ids carry the security, as every security has its own form.
  defp feed_form(security, changeset),
    do: to_form(changeset, as: :feed, id: "feed-#{security.id}")

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, reload(socket)}

  @impl true
  def handle_event("save_feed", %{"security_id" => id, "feed" => params}, socket) do
    security = security!(socket, id)

    case Securities.update_quote_feed(socket.assigns.current_scope, security, params) do
      {:ok, updated} ->
        if new_yahoo_source?(security, updated),
          do: MarketData.fetch_in_background(updated)

        {:noreply, socket |> load() |> push_saved("feed-#{security.id}-save")}

      {:error, changeset} ->
        {:noreply, put_form(socket, :feed_forms, security, feed_form(security, changeset))}
    end
  end

  def handle_event("save_benchmark", %{"benchmark" => %{"benchmark_id" => id}}, socket) do
    with {:ok, security_id} <- benchmark_id(id),
         {:ok, socket} <- pick_benchmark(socket, security_id) do
      message = if security_id, do: "Benchmark gespeichert.", else: "Keine Benchmark mehr."
      {:noreply, socket |> reload() |> put_flash(:info, message)}
    else
      :error -> {:noreply, socket |> reload() |> put_flash(:error, @unknown_benchmark)}
    end
  end

  def handle_event("create_security", %{"yahoo" => params}, socket) do
    with {:ok, security} <- MarketData.create_yahoo_security(socket.assigns.current_scope, params),
         {:ok, socket} <- pick_benchmark(socket, security.id) do
      socket
      |> assign(:symbol_form, symbol_form())
      |> load()
      |> put_flash(:info, "#{security.name} ist deine Benchmark.")
      |> then(&{:noreply, &1})
    else
      {:error, changeset} ->
        {:noreply, assign(socket, :symbol_form, symbol_form(changeset))}

      :error ->
        {:noreply, socket |> load() |> put_flash(:error, @unknown_benchmark)}
    end
  end

  defp benchmark_id(""), do: {:ok, nil}

  defp benchmark_id(id) do
    case parse_id(id) do
      nil -> :error
      security_id -> {:ok, security_id}
    end
  end

  defp pick_benchmark(socket, security_id) do
    case Settings.update_benchmark(socket.assigns.current_scope, security_id) do
      {:ok, _setting} -> {:ok, socket}
      {:error, _changeset} -> :error
    end
  end

  defp security!(socket, id), do: Map.fetch!(socket.assigns.securities, String.to_integer(id))

  defp new_yahoo_source?(before, updated),
    do:
      updated.quote_feed == :yahoo and
        {before.quote_feed, before.symbol} != {:yahoo, updated.symbol}

  defp put_form(socket, key, security, form),
    do: update(socket, key, &Map.put(&1, security.id, form))
end
