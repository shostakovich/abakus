defmodule AbakusWeb.Depot.WealthLive do
  @moduledoc """
  „Vermögen“: net worth with its curve, the Depot's returns and dividends, and the portfolios. For
  the budget owner net worth is the money in all accounts plus the value of the holdings, see
  `Abakus.Depot.Wealth`; for anyone else the value of their portfolios and Verrechnungskonten.
  """
  use AbakusWeb, :depot_live_view

  import AbakusWeb.Depot.DividendComponents

  alias Abakus.Depot.{Portfolios, Wealth}
  alias Abakus.{Format, LocalTime}
  alias Abakus.Money
  alias AbakusWeb.Areas
  alias AbakusWeb.Depot.{Benchmark, Periods}
  alias AbakusWeb.Depot.Format, as: DepotFormat

  on_mount Benchmark

  # The first is the default.
  @periods [
    {"6m", :six_months, "6\u00A0M", "6 Monate"},
    {"ytd", :year_to_date, "YTD", "YTD, seit Jahresbeginn"},
    {"1y", :one_year, "1\u00A0J", "1 Jahr"},
    {"max", :max, "Max", "Max, seit der ersten Buchung"}
  ]

  @upcoming_shown 4

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :periods, @periods)

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:wealth}
    >
      <.header>
        Vermögen
        <:actions>
          <Benchmark.toggle_button :if={@benchmark} shown={@benchmark_shown} />
          <.segmented
            id="period"
            label="Zeitraum"
            size={:sm}
            value={@period}
            block={:phone}
            options={Periods.options(@periods, &~p"/depot?#{[period: Periods.param(@periods, &1)]}")}
          />
        </:actions>
      </.header>

      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat id="net-worth" label="Vermögen" size={:sm}>
          <.amount value={@net_worth} decimals={0} />
          <:note><.change_note change={@change} percent={@change_percent} /></:note>
        </.stat>
        <.stat
          id="ttwror"
          label={join_meta(["TTWROR", period_label(@period)])}
          value={Format.signed_rate(@overview.ttwror, 2)}
          tone={sign(Format.signed_rate(@overview.ttwror, 2))}
          size={:sm}
        >
          <:note>
            <Benchmark.note :if={@benchmark_shown and @benchmark} benchmark={@benchmark} />
            <span :if={!(@benchmark_shown and @benchmark)}>zeitgewichtet</span>
          </:note>
        </.stat>
        <.stat
          id="irr"
          label={join_meta(["IZF", period_label(@period)])}
          value={Format.signed_rate(@overview.irr, 2)}
          tone={sign(Format.signed_rate(@overview.irr, 2))}
          desc={join_meta(["p.\u00A0a.", "geldgewichtet"])}
          size={:sm}
        />
        <.stat id="dividends" label={"Dividenden #{@today.year}"} size={:sm}>
          <.amount value={@overview.dividends} decimals={0} />
          <:note>
            erwartet
            <.amount
              value={@overview.dividends + @upcoming_dividends.rest_of_year}
              decimals={0}
            /> im Jahr<.meta_sep />brutto
          </:note>
        </.stat>
      </div>

      <.chart_card
        id="history"
        title="Wertentwicklung"
        hook="NetWorthChart"
        height={:lg}
        summary={chart_label(@period, @budget?, @benchmark_shown && @benchmark)}
        class="mt-4 md:mt-6"
      >
        <:legend>
          <.legend
            id="history-legend"
            items={legend_items(@budget?, @benchmark_shown && @benchmark)}
          />
        </:legend>
      </.chart_card>

      <div class="mt-8 grid gap-x-10 gap-y-8 xl:grid-cols-2">
        <.upcoming_dividends
          :if={@upcoming_dividends.upcoming != []}
          dividends={@upcoming_dividends}
        />
        <section
          :if={@overview.portfolios != []}
          id="portfolios"
          aria-labelledby="portfolios-title"
          class={@upcoming_dividends.upcoming == [] && "xl:col-span-2"}
        >
          <.section_heading id="portfolios-title">Depots</.section_heading>
          <.list>
            <.list_row
              :for={entry <- @overview.portfolios}
              id={"portfolio-#{entry.portfolio.id}"}
              title={DepotFormat.portfolio_name(entry.portfolio)}
              navigate={depots_path(:holdings, entry.portfolio.id)}
              trailing_on_phone={:title}
            >
              <:leading><.plush name="briefcase" size={:lg} /></:leading>
              <:meta>{portfolio_note(entry)}</:meta>
              <:trailing>
                <div class="text-end">
                  <.amount value={entry.value} class="font-semibold" />
                  <div
                    :if={entry.securities > 0}
                    class={["text-sm tabular-nums", tone(Format.signed_rate(entry.ttwror, 1))]}
                  >
                    {Format.signed_rate(entry.ttwror, 1)} YTD
                  </div>
                  <div :if={entry.securities == 0} class="text-sm text-base-content/70">nur Cash</div>
                </div>
              </:trailing>
            </.list_row>
          </.list>
        </section>
      </div>
    </Layouts.depot>
    """
  end

  attr :dividends, :map, required: true, doc: "see `Portfolios.upcoming_dividends/2`"

  defp upcoming_dividends(assigns) do
    assigns =
      assign(assigns,
        shown: Enum.take(assigns.dividends.upcoming, @upcoming_shown),
        three_months: assigns.dividends.next_three_months
      )

    ~H"""
    <section id="upcoming-dividends" aria-labelledby="upcoming-dividends-title">
      <.section_heading id="upcoming-dividends-title">
        Nächste Dividenden<span class="font-normal text-base-content/70"><.meta_sep />brutto</span>
        <:actions>
          <.button navigate={~p"/depot/dividends?amount=gross"} variant={:ghost} size={:sm}>
            Kalender<.icon name="chevron-right" />
          </.button>
        </:actions>
      </.section_heading>
      <.list>
        <.list_row
          :for={dividend <- @shown}
          title={security_title(dividend.security)}
          navigate={security_path(dividend.security)}
          data-kind={dividend.kind}
        >
          <:leading>
            <time
              class="flex w-10 flex-col items-center leading-tight"
              datetime={Date.to_iso8601(dividend.pay_date)}
            >
              <span class="text-xl font-bold tabular-nums">{dividend.pay_date.day}</span>
              <span class="text-xs text-base-content/70">{Format.month_abbr(dividend.pay_date)}</span>
            </time>
          </:leading>
          <:meta><.kind_tag kind={dividend.kind} /></:meta>
          <:trailing>
            <span class="font-semibold tabular-nums whitespace-nowrap">
              {expected(dividend, :gross, 2)}
            </span>
          </:trailing>
        </.list_row>
      </.list>
      <p id="upcoming-dividends-total" class="mt-2 text-sm text-base-content/70">
        Nächste 3 Monate:
        <strong class="text-base-content tabular-nums">
          {expected_total(@three_months, :gross, 0)}
        </strong>
      </p>
    </section>
    """
  end

  attr :change, :integer, required: true, doc: "since yesterday, in cents"
  attr :percent, :any, required: true, doc: "nil when there was nothing yesterday"

  defp change_note(assigns) do
    ~H"""
    <span class={amount_tone(@change, 0)}>
      <.amount value={@change} signed decimals={0} /> heute{percent_note(@percent)}
    </span>
    """
  end

  defp percent_note(nil), do: nil
  defp percent_note(percent), do: " (#{Format.signed_percent(percent)})"

  defp legend_items(true = _budget?, _benchmark),
    do: [%{label: "Vermögen", color: 1, marker: :line}]

  defp legend_items(false = _budget?, benchmark) do
    [
      %{label: "Vermögen", color: 1, marker: :line},
      %{label: "Investiert", color: 8, marker: :dashed}
    ] ++
      if benchmark, do: [Benchmark.legend_item(benchmark.security)], else: []
  end

  defp period_text(:six_months), do: "der letzten sechs Monate"
  defp period_text(:year_to_date), do: "seit Jahresbeginn"
  defp period_text(:one_year), do: "des letzten Jahres"
  defp period_text(:max), do: "seit der ersten Buchung"

  defp chart_label(period, true = _budget?, _benchmark),
    do: "Vermögen aus Konten und Wertpapieren #{period_text(period)}"

  defp chart_label(period, false = _budget?, %{security: security}),
    do:
      "Vermögen, investiertes Kapital und Schattendepot in #{security.name} #{period_text(period)}"

  defp chart_label(period, false = _budget?, _hidden),
    do: "Vermögen und investiertes Kapital #{period_text(period)}"

  defp period_label(period), do: Periods.label(@periods, period)

  # Each part stays on one line.
  defp portfolio_note(%{securities: count, cash: cash}),
    do: join_meta([securities(count), cash && "Cash\u00A0#{Money.euros(cash)}"])

  defp securities(0), do: "keine\u00A0Wertpapiere"
  defp securities(1), do: "1\u00A0Wertpapier"
  defp securities(count), do: "#{count}\u00A0Wertpapiere"

  @impl true
  def mount(_params, _session, socket) do
    budget? = Areas.allowed?(socket.assigns.current_scope, :budget)
    {:ok, assign(socket, page_title: "Vermögen", budget?: budget?)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(period: period(params["period"]))
    |> load_overview()
    |> load_upcoming_once()
    |> then(&{:noreply, &1})
  end

  defp period(param), do: Periods.parse(@periods, param, :six_months)

  @impl true
  def handle_info(:market_data_updated, socket),
    do: {:noreply, socket |> load_overview() |> load_upcoming()}

  defp load_overview(socket) do
    today = LocalTime.today()
    %{current_scope: scope, period: period, budget?: budget?} = socket.assigns
    overview = Portfolios.overview(scope, period, today)
    wealth = wealth(scope, budget?, overview, period, today)
    change = wealth.net_worth - wealth.net_worth_yesterday

    socket
    |> assign(
      today: today,
      overview: overview,
      benchmark: if(!budget?, do: overview.benchmark),
      net_worth: wealth.net_worth,
      change: change,
      change_percent: change_percent(change, wealth.net_worth_yesterday)
    )
    |> push_chart(wealth.chart)
  end

  defp wealth(_scope, false = _budget?, overview, _period, _today), do: overview

  defp wealth(scope, true = _budget?, overview, period, today),
    do: Wealth.of_budget_owner(scope, overview.first_day, period, today)

  defp load_upcoming_once(%{assigns: %{upcoming_dividends: _}} = socket), do: socket
  defp load_upcoming_once(socket), do: load_upcoming(socket)

  defp load_upcoming(%{assigns: assigns} = socket) do
    upcoming = Portfolios.upcoming_dividends(assigns.current_scope, assigns.today)
    assign(socket, upcoming_dividends: upcoming)
  end

  defp change_percent(_change, before) when before <= 0, do: nil
  defp change_percent(change, before), do: Format.percent_of(change, before)

  # The hook draws the chart once connected; amounts in cents.
  defp push_chart(socket, chart) do
    %{benchmark: benchmark, budget?: budget?} = socket.assigns

    if connected?(socket) do
      push_event(socket, "net-worth-chart", %{
        dates: Enum.map(chart, & &1.date),
        net_worth: Enum.map(chart, & &1.net_worth),
        invested_capital: if(!budget?, do: Enum.map(chart, & &1.invested_capital)),
        benchmark: benchmark && Enum.map(chart, & &1.benchmark),
        benchmark_name: benchmark_name(benchmark),
        benchmark_shown: socket.assigns.benchmark_shown
      })
    else
      socket
    end
  end

  defp benchmark_name(nil), do: nil
  defp benchmark_name(benchmark), do: Benchmark.short_name(benchmark.security.name)
end
