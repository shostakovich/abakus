defmodule AbakusWeb.Depot.SecurityLive do
  use AbakusWeb, :depot_live_view

  import AbakusWeb.Depot.{AllocationComponents, DividendComponents}

  alias Abakus.Depot.{MarketData, Portfolios, Securities}
  alias Abakus.{ExchangeRates, LocalTime}
  alias AbakusWeb.Depot.{AttributeValue, Format, Periods}

  # URL parameter, period, button label and its accessible name; the first is the default.
  @periods [
    {"1y", :one_year, "1\u00A0J", "1 Jahr"},
    {"5y", :five_years, "5\u00A0J", "5 Jahre"},
    {"max", :max, "Max", "Max, seit dem ersten Kurs"}
  ]

  # Composition tab, also its URL parameter, and label; the first is the default.
  @composition_tabs [regions: "Regionen", sectors: "Sektoren"]

  # The distributions shown until all are asked for.
  @recent_distributions 8

  # The sidebar marks „Depots“, which the page belongs to.
  @current {:depots, nil}

  @impl true
  def render(%{security: nil} = assigns) do
    assigns = assign(assigns, :current, @current)

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={@current}
    >
      <.header>Wertpapier nicht gefunden</.header>
      <.empty_state plush="layers" icon="layers">
        Unter dieser Adresse gibt es kein Wertpapier.
        <:action><.button navigate={~p"/depot/holdings"} size={:sm}>Zum Bestand</.button></:action>
      </.empty_state>
    </Layouts.depot>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, periods: @periods, current: @current)

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={@current}
    >
      <.header back={~p"/depot/holdings"} back_label="Bestand">
        {@security.name}
        <:subtitle>{subtitle(@security)}</:subtitle>
        <:actions>
          <div :if={@price} id="price" class="whitespace-nowrap tabular-nums sm:text-end">
            <div class="text-2xl font-bold">{Format.price(@price, @security.currency)}</div>
            <div
              :if={@price_yesterday}
              class={["text-sm", tone(change_note(@price, @price_yesterday, @security.currency))]}
            >
              {change_note(@price, @price_yesterday, @security.currency)}
            </div>
          </div>
          <.segmented
            id="period"
            label="Zeitraum"
            size={:sm}
            value={@period}
            block={:phone}
            class="self-center"
            options={Periods.options(@periods, &security_path(@security, &1, @composition_tab))}
          />
        </:actions>
      </.header>

      <%!-- One grid for both rows, so the columns line up. --%>
      <div class="grid items-start gap-x-10 gap-y-8 2xl:grid-cols-[3fr_2fr]">
        <.chart_card
          id="price-history"
          title="Kurs"
          hook={@chart.prices != [] && "PriceChart"}
          height={:lg}
          summary={
            if @chart.prices == [],
              do: "Keine Kurse in diesem Zeitraum",
              else: "Kursverlauf #{period_text(@period)}"
          }
          class="min-w-0"
        >
          <.empty_state id="price-chart-empty" plush="trending-up" icon="trending-up">
            Keine Kurse in diesem Zeitraum.
          </.empty_state>
          <:legend :if={@chart.prices != [] and @chart.trades != []}>
            <div id="price-chart-legend" class="flex flex-wrap items-center gap-x-4 gap-y-1">
              <.legend items={[%{label: "Kauf", color: :success}, %{label: "Verkauf", color: :error}]} />
              <span class="text-xs text-base-content/70">
                zum Preis je Stück vor Gebühren und Steuern
              </span>
            </div>
          </:legend>
        </.chart_card>
        <.holding holdings={@holdings} total={@total} />
        <div class="flex min-w-0 flex-col gap-8">
          <.upcoming_payments :if={@upcoming != []} upcoming={@upcoming} />
          <.distributions distributions={@distributions} />
          <.composition
            composition={@profile.composition}
            tab={@composition_tab}
            tabs={composition_tabs(assigns)}
            available={@compositions_available}
            isin={@security.isin}
          />
        </div>
        <div class="flex min-w-0 flex-col gap-8">
          <.profile profile={@profile} security={@security} costs_per_year={@costs_per_year} />
          <.sources
            security={@security}
            exchange_rate={@exchange_rate}
            composition={@profile.composition}
            available={@compositions_available}
          />
        </div>
      </div>
    </Layouts.depot>
    """
  end

  attr :holdings, :list, required: true
  attr :total, :map, required: true

  # Over all portfolios, then per portfolio when it is in several.
  defp holding(assigns) do
    ~H"""
    <section id="holding" aria-labelledby="holding-title">
      <.section_heading id="holding-title">Position</.section_heading>
      <.empty_state :if={@holdings == []} plush="briefcase" icon="briefcase">
        Nicht im Bestand.
      </.empty_state>
      <.description_list :if={@holdings != []} class="border-t border-base-content/10">
        <:item label="Stück">{Format.shares(@total.shares)}</:item>
        <:item label="Wert"><.amount value={@total.value} class="font-semibold" /></:item>
        <:item label="Einstand"><.amount value={@total.purchase_value} /></:item>
        <:item label="Gewinn">
          <.gain gain={@total.gain} purchase_value={@total.purchase_value} />
        </:item>
      </.description_list>
      <%!-- From sm the rows start at the facts' edge. --%>
      <.list :if={length(@holdings) > 1} id="holding-portfolios" class="mt-4 sm:[&>li]:px-0">
        <.list_row
          :for={entry <- @holdings}
          id={"holding-#{entry.portfolio.id}"}
          title={Format.portfolio_name(entry.portfolio)}
          navigate={depots_path(:holdings, entry.portfolio.id)}
          trailing_on_phone={:title}
        >
          <:leading><.plush name="briefcase" size={:lg} /></:leading>
          <:meta>{Format.shares(entry.shares)} Stück</:meta>
          <:trailing>
            <div class="text-end">
              <.amount value={entry.value} class="font-semibold" />
              <div class="text-sm"><.amount value={entry.gain} signed tone /></div>
            </div>
          </:trailing>
        </.list_row>
      </.list>
    </section>
    """
  end

  attr :upcoming, :list, required: true, doc: "see `Dividends.upcoming/4`"

  defp upcoming_payments(assigns) do
    assigns = assign(assigns, places: per_share_places(assigns.upcoming))

    ~H"""
    <section id="upcoming-payments" aria-labelledby="upcoming-payments-title">
      <.section_heading id="upcoming-payments-title">
        Nächste Zahlungen
        <:actions>
          <span class="text-sm whitespace-nowrap text-base-content/70">
            nächste 12 Monate <span class="tabular-nums">{expected_total(@upcoming, :gross, 2)}</span>
          </span>
        </:actions>
      </.section_heading>
      <.table id="upcoming-payment-rows" rows={@upcoming} size={:sm}>
        <:col :let={dividend} label="Zahltag">
          <time class="tabular-nums" datetime={Date.to_iso8601(dividend.pay_date)}>
            {Format.date(dividend.pay_date)}
          </time>
          <.cell_sub hide_from={:sm} class="tabular-nums">
            {Format.shares(dividend.shares)}&nbsp;Stück × {per_share(dividend, @places)}
          </.cell_sub>
        </:col>
        <:col :let={dividend} label="Ex-Tag" show_from={:sm}>
          <span class="tabular-nums text-base-content/70">{Format.short_date(dividend.ex_date)}</span>
        </:col>
        <:col :let={dividend} label="Art"><.kind_tag kind={dividend.kind} /></:col>
        <:col :let={dividend} label="je Anteil" align={:end} show_from={:sm}>
          {per_share(dividend, @places)}
        </:col>
        <:col :let={dividend} label="Stück" align={:end} show_from={:sm}>
          {Format.shares(dividend.shares)}
        </:col>
        <:col :let={dividend} label="Brutto" align={:end}>{expected(dividend, :gross, 2)}</:col>
      </.table>
      <p class="mt-2 max-w-prose text-sm text-base-content/70"><.forecast_note gross /></p>
    </section>
    """
  end

  defp per_share(%{kind: :forecast} = dividend, places),
    do: "~" <> per_share(%{dividend | kind: :announced}, places)

  defp per_share(dividend, places),
    do: Format.price(dividend.per_share, dividend.currency, places)

  defp per_share_places(rows) do
    for(%{per_share: per_share} when per_share != nil <- rows, do: Format.price_places(per_share))
    |> Enum.max(fn -> 2 end)
  end

  attr :distributions, :list, required: true, doc: "see `Distributions.of/3`"

  # The newest until all are asked for; the older rows stay hidden until then.
  defp distributions(assigns) do
    distributions = assigns.distributions

    assigns =
      assign(assigns,
        rows:
          distributions
          |> Enum.with_index()
          |> Enum.map(fn {entry, index} ->
            Map.put(entry, :older, index >= @recent_distributions)
          end),
        ex_dates: Enum.any?(distributions, & &1.ex_date),
        total: Enum.sum_by(distributions, & &1.gross),
        recent: @recent_distributions,
        places: per_share_places(distributions)
      )

    ~H"""
    <section id="distributions" aria-labelledby="distributions-title">
      <.section_heading id="distributions-title">
        Ausschüttungen je Anteil
        <:actions :if={@distributions != []}>
          <span id="distributions-total" class="text-sm whitespace-nowrap text-base-content/70">
            bisher gesamt <span class="tabular-nums">{Format.euros(@total, 2)}</span>
          </span>
        </:actions>
      </.section_heading>
      <.empty_state :if={@distributions == []} plush="coins" icon="coins">
        Keine Ausschüttungen gebucht.
      </.empty_state>
      <.table
        :if={@distributions != []}
        id="distribution-rows"
        rows={@rows}
        size={:sm}
        row_attrs={&%{hidden: &1.older}}
      >
        <:col :let={entry} label="Zahltag">
          <time class="tabular-nums" datetime={Date.to_iso8601(entry.date)}>
            {Format.date(entry.date)}
          </time>
        </:col>
        <:col :let={entry} :if={@ex_dates} label="Ex-Tag" show_from={:sm}>
          <span class="tabular-nums text-base-content/70">{Format.short_date(entry.ex_date)}</span>
        </:col>
        <:col :let={entry} label="je Anteil" align={:end}>
          {Format.price(entry.per_share, entry.currency, @places)}
        </:col>
        <:col :let={entry} label="Stück" align={:end} show_from={:sm}>
          {if entry.shares > 0, do: Format.shares(entry.shares), else: "–"}
        </:col>
        <:col :let={entry} label="Brutto" align={:end}><.amount value={entry.gross} /></:col>
      </.table>
      <div
        :if={@distributions != []}
        class="mt-2 flex flex-wrap items-center justify-between gap-2 text-sm text-base-content/70"
      >
        <span>Aus deinen gebuchten Dividenden, vor Steuern und Gebühren.</span>
        <.button
          :if={length(@distributions) > @recent}
          id="distributions-all"
          variant={:ghost}
          size={:sm}
          phx-click={JS.remove_attribute("hidden", to: "#distribution-rows tr[hidden]") |> JS.hide()}
        >
          Alle {length(@distributions)} anzeigen<.icon name="chevron-down" />
        </.button>
      </div>
    </section>
    """
  end

  attr :composition, :map, required: true, doc: "see `Allocation.of_composition/1`, or nil"
  attr :tab, :atom, required: true
  attr :tabs, :list, required: true
  attr :available, :boolean, required: true, doc: "whether DivvyDiary has its API key"
  attr :isin, :string, required: true

  # Regions and sectors as the holdings show them, if DivvyDiary delivered them.
  defp composition(assigns) do
    assigns = assign(assigns, :shown, assigns.available and assigns.composition != nil)

    ~H"""
    <section id="composition" aria-labelledby="composition-title">
      <.section_heading id="composition-title">Zusammensetzung</.section_heading>
      <.tabs :if={@shown} label="Zusammensetzung nach" class="mb-4">
        <:tab :for={tab <- @tabs} patch={tab.path} active={tab.active}>{tab.label}</:tab>
      </.tabs>
      <.missing_key :if={!@available} />
      <.empty_state :if={@available and !@composition} plush="layers" icon="layers">
        {if @isin in [nil, ""],
          do: "Ohne ISIN fragt Abakus DivvyDiary nicht nach Ländern und Sektoren.",
          else: "Von DivvyDiary liegen für dieses Wertpapier keine Länder und Sektoren vor."}
      </.empty_state>
      <.composition_bars :if={@shown} id="composition-rows" rows={Map.fetch!(@composition, @tab)} />
      <p :if={@shown} class="mt-4 text-sm text-base-content/70">
        Länder und Sektoren von DivvyDiary, Stand {Format.date(@composition.as_of)}.
      </p>
    </section>
    """
  end

  attr :profile, :map, required: true, doc: "see `Securities.profile/2`"
  attr :security, :map, required: true
  attr :costs_per_year, :integer, required: true, doc: "of the user's holdings, nil without"

  # TER and fund size as the costs on the holdings screen show them, then every other attribute
  # under the name of its type.
  defp profile(assigns) do
    assigns = assign(assigns, :rows, profile_rows(assigns))

    ~H"""
    <section id="profile" aria-labelledby="profile-title">
      <.section_heading id="profile-title">Steckbrief</.section_heading>
      <.empty_state :if={@rows == []} plush="layers" icon="layers">
        Keine Angaben aus Portfolio Performance.
      </.empty_state>
      <.description_list :if={@rows != []} class="border-t border-base-content/10">
        <:item :for={{label, value} <- @rows} label={label}><.attribute value={value} /></:item>
      </.description_list>
    </section>
    """
  end

  defp profile_rows(%{profile: profile, security: security, costs_per_year: costs_per_year}) do
    ter =
      if profile.ter,
        do: [{"TER", {:text, ter(profile.ter, costs_per_year)}}],
        else: []

    fund_size =
      if profile.fund_size,
        do: [{"Fondsgröße", {:text, Format.fund_size(profile.fund_size, security.currency)}}],
        else: []

    attributes =
      for {type, value} <- profile.attributes,
          shown = AttributeValue.display(type, value, security.currency),
          do: {attribute_label(type), shown}

    ter ++ fund_size ++ attributes
  end

  defp ter(ter, nil), do: Format.ter(ter)
  defp ter(ter, per_year), do: join_meta([Format.ter(ter), "#{Format.euros(per_year)} im Jahr"])

  # PP names its built-in attributes in the language the file was created in; its English
  # default for the vendor reads in German here. A name the user chose stays.
  defp attribute_label(%{pp_id: "vendor", name: "Vendor"}), do: "Anbieter"
  defp attribute_label(type), do: type.name

  attr :value, :any, required: true, doc: "see `AttributeValue.display/3`"

  defp attribute(%{value: {:text, text}} = assigns) do
    assigns = assign(assigns, :text, text)
    ~H"{@text}"
  end

  defp attribute(%{value: {:link, label, url}} = assigns) do
    assigns = assign(assigns, label: label, url: url)

    ~H"""
    <a href={@url} target="_blank" rel="noopener noreferrer" class="link">{@label}</a>
    """
  end

  defp attribute(%{value: {:image, uri}} = assigns) do
    assigns = assign(assigns, :uri, uri)

    ~H"""
    <img src={@uri} alt="" height="32" />
    """
  end

  attr :security, :map, required: true
  attr :exchange_rate, :map, required: true, doc: "the latest of its currency, nil without"
  attr :composition, :map, required: true
  attr :available, :boolean, required: true

  defp sources(assigns) do
    ~H"""
    <section id="sources" aria-labelledby="sources-title">
      <.section_heading id="sources-title">Datenquellen</.section_heading>
      <.description_list class="border-t border-base-content/10">
        <:item label="Kurse">
          <div :if={@security.quote_feed == :yahoo}>
            <p>Yahoo<.meta_sep /><code>{@security.symbol}</code></p>
            <p :if={@security.fetch_error} class="font-normal text-error-ink">
              {@security.fetch_error}
            </p>
            <p :if={!@security.fetch_error} class="font-normal text-base-content/70">
              {fetched(@security.fetched_at)}
            </p>
          </div>
          <div :if={@security.quote_feed == :manual}>
            <p>Portfolio Performance</p>
            <p class="font-normal text-base-content/70">nur aus dem PP-Import</p>
          </div>
        </:item>
        <:item :if={@security.currency != "EUR"} label={"Wechselkurs #{@security.currency}"}>
          <p>{join_meta(["EZB", @exchange_rate && Format.rate(@exchange_rate.rate)])}</p>
          <p class="font-normal text-base-content/70">
            {if @exchange_rate,
              do: "Stand #{Format.date(@exchange_rate.date)}",
              else: "noch kein Kurs"}
          </p>
        </:item>
        <:item label="Länder und Sektoren">
          <p>DivvyDiary</p>
          <p class="font-normal text-base-content/70">
            {composition_source(@available, @composition, @security.isin)}
          </p>
        </:item>
      </.description_list>
      <.button
        navigate={"#{~p"/depot/securities"}#security-#{@security.id}"}
        size={:sm}
        class="mt-4"
      >
        Kursquelle ändern
      </.button>
    </section>
    """
  end

  defp fetched(nil), do: "noch nicht abgerufen"
  defp fetched(at), do: "abgerufen #{Format.datetime(at)}"

  defp composition_source(false = _available, _composition, _isin), do: "ohne API-Key"
  defp composition_source(true, %{as_of: as_of}, _isin), do: "Stand #{Format.date(as_of)}"
  defp composition_source(true, nil, isin) when isin in [nil, ""], do: "ohne ISIN"
  defp composition_source(true, nil, _isin), do: "keine Angaben"

  # Regions and sectors; each keeps the period.
  defp composition_tabs(assigns) do
    for {tab, label} <- @composition_tabs do
      %{
        label: label,
        path: security_path(assigns.security, assigns.period, tab),
        active: tab == assigns.composition_tab
      }
    end
  end

  # The security page with `period` and the composition `tab`, the defaults left out.
  defp security_path(security, period, tab) do
    query =
      Enum.filter(
        [
          period: period != :one_year && Periods.param(@periods, period),
          composition: tab != :regions && Atom.to_string(tab)
        ],
        &elem(&1, 1)
      )

    ~p"/depot/securities/#{security}?#{query}"
  end

  defp subtitle(security),
    do: join_meta([security.isin, security.wkn && "WKN #{security.wkn}", security.currency])

  defp change_note(price, yesterday, currency) do
    change = price - yesterday

    percent =
      if yesterday > 0,
        do: " (#{change |> Format.percent_of(yesterday) |> Format.signed_percent()})"

    "#{Format.signed_price(change, currency)}#{percent} heute"
  end

  defp period_text(:one_year), do: "des letzten Jahres"
  defp period_text(:five_years), do: "der letzten fünf Jahre"
  defp period_text(:max), do: "seit dem ersten Kurs"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     assign(socket,
       security_id: parse_id(id),
       compositions_available: MarketData.divvy_diary_available?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(period: period(params["period"]))
    |> assign(composition_tab: composition_tab(params["composition"]))
    |> load()
    |> then(&{:noreply, &1})
  end

  defp period(param), do: Periods.parse(@periods, param, :one_year)

  defp composition_tab("sectors"), do: :sectors
  defp composition_tab(_default), do: :regions

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load(socket)}

  # The security again each time, with its latest quote.
  defp load(socket) do
    %{current_scope: scope, security_id: id, period: period} = socket.assigns

    case id && Securities.get_security(scope, id) do
      nil ->
        assign(socket, security: nil, page_title: "Nicht gefunden")

      security ->
        shown = Portfolios.security(scope, security, period, LocalTime.today())

        socket
        |> assign(security: security, page_title: security.name)
        |> assign(shown)
        |> assign(profile: Securities.profile(scope, security))
        |> assign(exchange_rate: exchange_rate(security))
        |> push_chart(shown.chart)
    end
  end

  defp exchange_rate(%{currency: "EUR"}), do: nil
  defp exchange_rate(%{currency: currency}), do: ExchangeRates.latest(currency)

  # The hook draws the chart once connected; prices and shares × 10⁸.
  defp push_chart(socket, chart) do
    if connected?(socket) do
      push_event(socket, "price-chart", %{
        currency: Format.currency(socket.assigns.security.currency),
        dates: Enum.map(chart.prices, & &1.date),
        prices: Enum.map(chart.prices, & &1.price),
        trades: chart.trades
      })
    else
      socket
    end
  end
end
