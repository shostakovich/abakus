defmodule AbakusWeb.Depot.DividendsLive do
  use AbakusWeb, :depot_live_view

  import AbakusWeb.Depot.DividendComponents

  alias Abakus.Depot.Portfolios
  alias Abakus.{Format, LocalTime, Money}
  alias AbakusWeb.Depot.Format, as: DepotFormat

  # The first is the default and stays out of the URL.
  @tabs [
    {"calendar", :calendar, "Kalender"},
    {"months", :months, "Monate"},
    {"received", :received, "Erhalten"}
  ]
  @amounts [{"net", :net, "Netto"}, {"gross", :gross, "Brutto"}]

  # The chart series of the years shown, the oldest first: this year 1, the year before 2.
  @year_colours ~w(chart-8 chart-2 chart-1)
  @recent_years 2

  @impl true
  def render(assigns) do
    assigns = assign(assigns, tabs: @tabs, amounts: @amounts)

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
      current={{:depots, @portfolio_id}}
    >
      <.depots_header
        tab={:dividends}
        portfolio={@dividends.portfolio}
        portfolios={@dividends.portfolios}
        switch_path={&dividends_path(@tab, @amount, &1)}
      >
        <:subtitle :if={any?(assigns)}>{subtitle(@tab)}</:subtitle>
        <:actions :if={any?(assigns)}>
          <.segmented
            id="amount"
            label="Betrag"
            size={:sm}
            value={@amount}
            options={
              for {_param, amount, label} <- @amounts,
                  do: {label, amount, dividends_path(@tab, amount, @portfolio_id)}
            }
          />
        </:actions>
      </.depots_header>

      <.empty_state
        :if={!any?(assigns)}
        id="dividends-empty"
        layout={:page}
        plush="coins"
        icon="coins"
        title="Noch keine Dividenden"
      >
        Hier erscheinen gebuchte Dividenden und die der nächsten 12&nbsp;Monate.
      </.empty_state>

      <%= if any?(assigns) do %>
        <.key_figures dividends={@dividends} amount={@amount} today={@today} />

        <.tabs id="dividend-tabs" label="Ansicht" class="mt-8 mb-6">
          <:tab
            :for={{_param, tab, label} <- @tabs}
            patch={dividends_path(tab, @amount, @portfolio_id)}
            active={@tab == tab}
          >
            {label}
          </:tab>
        </.tabs>

        <.calendar
          :if={@tab == :calendar}
          upcoming={@dividends.upcoming}
          months={@dividends.months}
          amount={@amount}
        />
        <%= if @tab != :calendar and @dividends.received == [] do %>
          <.empty_state plush="coins" icon="coins">Noch keine Dividenden gebucht.</.empty_state>
        <% else %>
          <.per_month
            :if={@tab == :months}
            years={@dividends.years}
            amount={@amount}
            today={@today}
          />
          <.received :if={@tab == :received} received={@dividends.received} />
        <% end %>
      <% end %>
    </Layouts.depot>
    """
  end

  attr :dividends, :map, required: true, doc: "see `Portfolios.dividends/2`"
  attr :amount, :atom, required: true
  attr :today, Date, required: true

  defp key_figures(assigns) do
    assigns =
      assign(assigns,
        next: List.first(assigns.dividends.upcoming),
        partly_gross: partly_gross?(assigns.dividends.upcoming, assigns.amount)
      )

    ~H"""
    <div id="key-figures" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <.stat id="next-12-months" label="Nächste 12 Monate" size={:sm}>
        <.quiet :if={@partly_gross}><.partly_gross /></.quiet>
        <.amount value={@dividends.total[@amount]} decimals={0} />
        <:note>
          <span class="whitespace-nowrap">
            Ø
            <.amount value={div(@dividends.total[@amount], 12)} decimals={0} /><span class="max-sm:hidden"> pro Monat</span><span class="sm:hidden">/Monat</span>
          </span>
        </:note>
      </.stat>
      <.stat id="this-year" label={"#{@today.year} bisher"} size={:sm}>
        <.amount value={@dividends.this_year[@amount]} decimals={0} />
        <:note>
          {@today.year - 1} gesamt <.amount value={@dividends.last_year[@amount]} decimals={0} />
        </:note>
      </.stat>
      <.stat id="yield" label="Rendite auf Wert" size={:sm}>
        <.quiet :if={@partly_gross}><.partly_gross /></.quiet>
        {yield(@dividends.total[@amount], @dividends.value)}
        <:note>
          <span class="whitespace-nowrap">
            auf Einstand {yield(@dividends.total[@amount], @dividends.purchase_value)}
          </span>
        </:note>
      </.stat>
      <.stat id="next-dividend" label="Nächste Dividende" size={:sm}>
        <.quiet :if={@next && @amount == :net && @next.net_is_gross}>
          <span title="Noch keine Dividende gebucht, aus der sich Steuern schätzen ließen">
            brutto
          </span>
        </.quiet>
        {if @next, do: expected(@next, @amount, 0), else: "–"}
        <:note>
          <span :if={@next} class="line-clamp-2">
            <.pay_date date={@next.pay_date} /><.meta_sep />{security_name(@next.security)}
          </span>
          <span :if={!@next}>keine erwartet</span>
        </:note>
      </.stat>
    </div>
    """
  end

  slot :inner_block, required: true

  # A remark before a key figure's value, such as „brutto“.
  defp quiet(assigns) do
    ~H"""
    <span class="text-sm font-normal text-base-content/70">{render_slot(@inner_block)}</span>
    """
  end

  attr :upcoming, :list, required: true, doc: "see `Dividends.upcoming/4`"
  attr :months, :list, required: true, doc: "see `Dividends.by_coming_month/2`"
  attr :amount, :atom, required: true

  defp calendar(assigns) do
    groups = Enum.chunk_by(assigns.upcoming, &{&1.pay_date.year, &1.pay_date.month})
    amount = assigns.amount

    # Twelve empty months say nothing the empty calendar does not say already.
    chart? = Enum.any?(assigns.months, &(&1.announced[amount] + &1.forecast[amount] > 0))
    assigns = assign(assigns, groups: groups, chart?: chart?)

    ~H"""
    <div class={["grid items-start gap-x-10 gap-y-8", @chart? && "xl:grid-cols-[3fr_2fr]"]}>
      <section id="calendar" aria-label="Kalender">
        <.empty_state :if={@groups == []} plush="coins" icon="coins">
          In den nächsten 12 Monaten ist keine Dividende angekündigt oder zu erwarten.
        </.empty_state>
        <.list :if={@groups != []}>
          <%= for [%{pay_date: first} | _] = dividends <- @groups do %>
            <.list_heading>
              <h2
                id={"calendar-#{Calendar.strftime(first, "%Y-%m")}"}
                class="flex flex-wrap items-baseline justify-between gap-x-3"
              >
                <span>{Format.month_year(first)}</span>
                <span class="tabular-nums">
                  <.partly_gross :if={partly_gross?(dividends, @amount)} class="font-normal" />
                  {expected_total(dividends, @amount, 2)}
                </span>
              </h2>
            </.list_heading>
            <.list_row
              :for={dividend <- dividends}
              title={security_title(dividend.security)}
              navigate={security_path(dividend.security)}
              data-pay-date={Date.to_iso8601(dividend.pay_date)}
              data-kind={dividend.kind}
            >
              <:meta>
                <span class="whitespace-nowrap">Zahltag <.pay_date date={dividend.pay_date} /></span><span
                  :if={dividend.ex_date}
                  class="whitespace-nowrap"
                ><.meta_sep />Ex‑Tag <.pay_date date={dividend.ex_date} /></span><.meta_sep /><span class="whitespace-nowrap">{DepotFormat.shares(
                  dividend.shares
                )}&nbsp;Stück × {per_share(dividend)}</span>
              </:meta>
              <:trailing>
                <.kind_tag kind={dividend.kind} />
                <span class="font-semibold tabular-nums whitespace-nowrap">
                  <span
                    :if={@amount == :net and dividend.net_is_gross}
                    class="text-sm font-normal text-base-content/70"
                    title="Noch keine Dividende gebucht, aus der sich Steuern schätzen ließen"
                  >
                    brutto
                  </span>
                  {expected(dividend, @amount, 2)}
                </span>
              </:trailing>
            </.list_row>
          <% end %>
        </.list>
      </section>
      <.chart_card
        :if={@chart?}
        id="coming-months"
        title={coming_months_title(@upcoming, @amount)}
        hook="UpcomingDividendChart"
        summary={coming_months_label(@months, @amount)}
        class="min-w-0 xl:sticky xl:top-6"
      >
        <:legend>
          <%!-- As <.legend>, which has no marker for a series' fill mixed lighter. --%>
          <ul class="flex flex-wrap gap-x-4 gap-y-1 text-xs">
            <li class="flex items-center gap-1.5">
              <span
                class="size-2.5 rounded-full border border-chart-1 bg-chart-1-fill"
                aria-hidden="true"
              ></span>
              angekündigt
            </li>
            <li class="flex items-center gap-1.5">
              <span
                class="size-2.5 rounded-full border border-chart-1 bg-chart-1-fill/35"
                aria-hidden="true"
              ></span>
              Prognose
            </li>
          </ul>
          <p class="text-sm text-base-content/70"><.forecast_note /></p>
        </:legend>
      </.chart_card>
    </div>
    """
  end

  attr :class, :any, default: nil

  defp partly_gross(assigns) do
    ~H"""
    <span
      class={@class}
      title="Enthält Dividenden ohne gebuchte Vorjahresdividende, brutto gezählt"
    >
      teils brutto
    </span>
    """
  end

  defp partly_gross?(upcoming, amount),
    do: amount == :net and Enum.any?(upcoming, & &1.net_is_gross)

  attr :years, :list, required: true, doc: "see `Dividends.by_year/2`"
  attr :amount, :atom, required: true
  attr :today, Date, required: true

  defp per_month(assigns) do
    colours = assigns.years |> chart_years() |> year_colours()

    assigns =
      assign(assigns,
        months: Enum.with_index(Enum.map(1..12, &Format.month_abbr/1)),
        colours: colours,
        colour: Map.new(colours)
      )

    ~H"""
    <div id="per-month" class="flex flex-col gap-8">
      <.chart_card
        id="dividend"
        title={join_meta(["Dividenden pro Monat", amount_label(@amount)])}
        hook="DividendChart"
        height={:lg}
        summary={"Dividenden pro Monat für #{chart_label(@colours)}"}
      >
        <:legend>
          <.legend items={
            for {year, colour} <- @colours, do: %{label: to_string(year), color: series(colour)}
          } />
        </:legend>
      </.chart_card>

      <section aria-labelledby="years-title">
        <.section_heading id="years-title">Jahre</.section_heading>
        <.table id="years" rows={@years} row_id={&"year-#{&1.year}"} size={:sm}>
          <:col :let={year} label="Jahr">
            <span class="inline-flex items-center gap-2 font-medium tabular-nums">
              <span class={["size-2.5 rounded-full", swatch(@colour[year.year])]} aria-hidden="true"></span>
              {year.year}
            </span>
            <.cell_sub :if={year.year == @today.year}>
              {so_far(@today)}<span :if={open?(year, @amount, @today)}><.meta_sep />noch offen</span>
            </.cell_sub>
          </:col>
          <:col
            :let={year}
            :for={{month, index} <- @months}
            label={month}
            align={:end}
            show_from={:"2xl"}
          >
            <% amount = month_cell(year, index, @amount, @today) %>
            <span :if={is_nil(amount)} class="sr-only">noch offen</span>
            <span :if={amount == 0} class="text-base-content/70">–</span>
            <.amount :if={amount not in [nil, 0]} value={amount} decimals={0} />
          </:col>
          <:col :let={year} label="Gesamt" align={:end}>
            <.amount value={year[@amount]} decimals={0} class="font-semibold" />
          </:col>
        </.table>
      </section>
    </div>
    """
  end

  attr :received, :list, required: true, doc: "see `Dividends.received/2`"

  # A group per year; the older years show their totals, their payments stay hidden until asked
  # for.
  defp received(assigns) do
    groups =
      assigns.received
      |> Enum.chunk_by(& &1.date.year)
      |> Enum.with_index()
      |> Enum.map(fn {[%{date: %{year: year}} | _] = rows, index} ->
        older = index >= @recent_years

        %{
          id: Integer.to_string(year),
          label: year_label(%{year: year, rows: rows}),
          rows: Enum.map(rows, &Map.put(&1, :older, older))
        }
      end)

    assigns = assign(assigns, groups: groups, recent: @recent_years)

    ~H"""
    <section id="received" aria-label="Erhaltene Dividenden">
      <.table id="received-years" groups={@groups} row_attrs={&%{hidden: &1.older}}>
        <:col :let={entry} label="Zahltag" show_from={:sm}>
          <.pay_date date={entry.date} />
        </:col>
        <:col :let={entry} label="Wertpapier">
          <.security_link security={entry.security} />
          <.cell_sub hide_from={:lg} class="tabular-nums">
            <span class="sm:hidden"><.pay_date date={entry.date} /><.meta_sep /></span><span class="whitespace-nowrap">{shares(
              entry.shares
            )}</span><.meta_sep /><span class="whitespace-nowrap">Steuern {Money.euros(entry.taxes)}</span><span
              :if={entry.fees != 0}
              class="whitespace-nowrap"
            ><.meta_sep />Gebühren {Money.euros(entry.fees)}</span>
          </.cell_sub>
          <.cell_sub show_from={:lg} hide_from={:xl} class="tabular-nums">
            {shares(entry.shares)}
          </.cell_sub>
        </:col>
        <:col :let={entry} label="Stück" align={:end} show_from={:xl}>
          {share_count(entry.shares)}
        </:col>
        <:col :let={entry} label="Brutto" align={:end} show_from={:sm}>
          <.amount value={entry.gross} />
        </:col>
        <:col :let={entry} label="Steuern" align={:end} show_from={:lg}>
          <span class={muted(entry.taxes)}>{deduction(entry.taxes)}</span>
        </:col>
        <:col :let={entry} label="Gebühren" align={:end} show_from={:lg}>
          <span class={muted(entry.fees)}>{deduction(entry.fees)}</span>
        </:col>
        <:col :let={entry} label="Netto" align={:end}>
          <.amount value={entry.net} class="font-semibold" />
          <.cell_sub hide_from={:sm}>brutto <.amount value={entry.gross} /></.cell_sub>
        </:col>
      </.table>
      <.button
        :if={length(@groups) > @recent}
        id="received-all"
        variant={:ghost}
        class="mt-2 w-full"
        phx-click={JS.remove_attribute("hidden", to: "#received-years tr[hidden]") |> JS.hide()}
      >
        Zahlungen älterer Jahre anzeigen<.icon name="chevron-down" />
      </.button>
    </section>
    """
  end

  attr :year, :integer, required: true
  attr :rows, :list, required: true

  # A year's group row: the year with its gross and net total.
  defp year_label(assigns) do
    ~H"""
    <span class="flex flex-wrap items-baseline justify-between gap-x-4">
      <span class="tabular-nums">{@year}</span>
      <span class="font-normal tabular-nums">
        brutto <.amount value={sum(@rows, :gross)} /><.meta_sep />netto
        <.amount value={sum(@rows, :net)} class="font-semibold" />
      </span>
    </span>
    """
  end

  # The months of this year paid so far: up to this month if anything came in yet, else the one
  # before.
  defp paid_months(%{year: year, months: months}, amount, %Date{year: year} = today),
    do: if(Enum.at(months, today.month - 1)[amount] > 0, do: today.month, else: today.month - 1)

  defp paid_months(_year, _amount, _today), do: 12

  defp open?(year, amount, today), do: paid_months(year, amount, today) < 12

  # A month's amount, nil for one still to come.
  defp month_cell(year, index, amount, today) do
    if index < paid_months(year, amount, today), do: Enum.at(year.months, index)[amount]
  end

  defp so_far(today), do: "bis #{today.day}. #{Format.month_abbr(today)}"

  attr :date, Date, required: true

  defp pay_date(assigns) do
    ~H"""
    <time datetime={Date.to_iso8601(@date)}>{Format.date(@date, year: false)}</time>
    """
  end

  defp sum(rows, key), do: Enum.sum_by(rows, &Map.fetch!(&1, key))

  @swatches %{
    "chart-1" => "border border-chart-1 bg-chart-1-fill",
    "chart-2" => "border border-chart-2 bg-chart-2-fill",
    "chart-8" => "border border-chart-8 bg-chart-8-fill"
  }

  defp series("chart-" <> n), do: String.to_integer(n)

  defp swatch(nil), do: "invisible"
  defp swatch(colour), do: Map.fetch!(@swatches, colour)

  defp deduction(0), do: "–"
  defp deduction(cents), do: Money.euros(cents)

  defp any?(%{dividends: dividends}), do: dividends.received != [] or dividends.upcoming != []

  defp subtitle(:calendar), do: "Termine von DivvyDiary, Prognose aus 12\u00A0Monaten"
  defp subtitle(_tab), do: "Gebucht, zum EZB\u2011Kurs des Zahltags"

  defp per_share(dividend),
    do: DepotFormat.price(dividend.per_share, dividend.currency)

  defp yield(_cents, 0), do: "–"
  defp yield(cents, whole), do: cents |> Format.percent_of(whole) |> Format.percent()

  defp coming_months_title(upcoming, amount) do
    title = join_meta(["Nächste 12 Monate", amount_label(amount)])
    if partly_gross?(upcoming, amount), do: title <> ", teils brutto", else: title
  end

  defp coming_months_label(months, amount) do
    "Erwartete Dividenden " <>
      Enum.map_join(months, ", ", fn month ->
        cents = month.announced[amount] + month.forecast[amount]
        "#{Format.month_year(month.month)} #{Money.euros(cents, decimals: 0)}"
      end)
  end

  defp amount_label(:net), do: "netto"
  defp amount_label(:gross), do: "brutto"

  defp shares(0), do: "–"
  defp shares(shares), do: "#{DepotFormat.shares(shares)}\u00A0Stück"

  defp share_count(0), do: "–"
  defp share_count(shares), do: DepotFormat.shares(shares)

  defp chart_years(years), do: years |> Enum.take(length(@year_colours)) |> Enum.reverse()

  defp year_colours(years),
    do: Enum.zip(Enum.map(years, & &1.year), Enum.take(@year_colours, -length(years)))

  defp chart_label(colours), do: Enum.map_join(colours, ", ", &elem(&1, 0))

  defp dividends_path(tab, amount, portfolio_id) do
    query =
      Enum.reject(
        [tab: param(@tabs, tab), amount: param(@amounts, amount), portfolio: portfolio_id],
        fn {_key, value} -> is_nil(value) end
      )

    ~p"/depot/dividends?#{query}"
  end

  defp param([{_param, value, _label} | _rest], value), do: nil

  defp param(choices, value),
    do: Enum.find_value(choices, fn {param, v, _label} -> v == value && param end)

  defp parse(choices, param) do
    [{_param, default, _label} | _rest] = choices
    Enum.find_value(choices, default, fn {p, value, _label} -> p == param && value end)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dividenden")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(tab: parse(@tabs, params["tab"]), amount: parse(@amounts, params["amount"]))
    |> show_or_load_dividends(parse_id(params["portfolio"]))
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_dividends(socket)}

  defp show_or_load_dividends(%{assigns: %{requested_id: id, dividends: _}} = socket, id),
    do: push_chart(socket)

  defp show_or_load_dividends(socket, portfolio_id),
    do:
      socket |> assign(requested_id: portfolio_id, portfolio_id: portfolio_id) |> load_dividends()

  defp load_dividends(socket) do
    %{current_scope: scope, portfolio_id: portfolio_id} = socket.assigns
    today = LocalTime.today()
    dividends = Portfolios.dividends(scope, portfolio_id, today)

    socket
    |> assign(
      today: today,
      dividends: dividends,
      portfolio_id: dividends.portfolio && dividends.portfolio.id
    )
    |> push_chart()
  end

  defp push_chart(%{assigns: %{tab: :months} = assigns} = socket) do
    years = chart_years(assigns.dividends.years)

    if connected?(socket) do
      push_event(socket, "dividend-chart", %{
        years:
          for {year, {_year, colour}} <- Enum.zip(years, year_colours(years)) do
            %{
              year: year.year,
              colour: colour,
              amounts: Enum.map(year.months, & &1[assigns.amount])
            }
          end
      })
    else
      socket
    end
  end

  defp push_chart(%{assigns: %{tab: :calendar} = assigns} = socket) do
    if connected?(socket) do
      push_event(socket, "upcoming-dividend-chart", %{
        months:
          for month <- assigns.dividends.months do
            %{
              label: Format.month_abbr(month.month),
              year: if(month.month.month == 1, do: month.month.year),
              title: Format.month_year(month.month),
              announced: month.announced[assigns.amount],
              forecast: month.forecast[assigns.amount]
            }
          end
      })
    else
      socket
    end
  end

  defp push_chart(socket), do: socket
end
