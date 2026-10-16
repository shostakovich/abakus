defmodule AbakusWeb.Depot.PerformanceLive do
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.Portfolios
  alias Abakus.LocalTime
  alias AbakusWeb.Depot.{Benchmark, Format, Periods}

  on_mount Benchmark

  # URL parameter, period, button label and its accessible name; the default is the year to date.
  @periods [
    {"1m", :one_month, "1\u00A0M", "1 Monat"},
    {"6m", :six_months, "6\u00A0M", "6 Monate"},
    {"ytd", :year_to_date, "YTD", "YTD, seit Jahresbeginn"},
    {"1y", :one_year, "1\u00A0J", "1 Jahr"},
    {"3y", :three_years, "3\u00A0J", "3 Jahre"},
    {"max", :max, "Max", "Max, seit der ersten Buchung"}
  ]
  @default_period :year_to_date

  @impl true
  def render(assigns) do
    assigns = assign(assigns, periods: @periods, per_year: "p. a.")

    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={{:depots, @performance.portfolio && @performance.portfolio.id, nil}}
    >
      <.depots_header
        tab={:performance}
        portfolio={@performance.portfolio}
        portfolios={@performance.portfolios}
        inbox={@depot_sidebar.inbox}
        switch_path={&performance_path(@period, &1)}
      >
        <:subtitle>
          <span class="whitespace-nowrap">{days(@performance.interval)}</span><.meta_sep /><span class="whitespace-nowrap">{portfolio_name(
            @performance.portfolio
          )}</span>
        </:subtitle>
        <:actions>
          <Benchmark.toggle_button :if={@performance.benchmark} shown={@benchmark_shown} />
          <.segmented
            id="period"
            label="Zeitraum"
            size={:sm}
            value={@period}
            block={:phone}
            options={Periods.options(@periods, &performance_path(&1, @performance.portfolio))}
          />
        </:actions>
      </.depots_header>

      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat
          id="ttwror"
          label="TTWROR"
          value={Format.signed_rate(@performance.ttwror, 2)}
          tone={sign(Format.signed_rate(@performance.ttwror, 2))}
          size={:sm}
        >
          <:note>
            <Benchmark.note
              :if={@benchmark_shown and @performance.benchmark}
              benchmark={@performance.benchmark}
            />
            <span :if={!(@benchmark_shown and @performance.benchmark)}>
              {Format.signed_rate(@performance.ttwror_per_year, 2)} {@per_year}
            </span>
          </:note>
        </.stat>
        <.stat
          id="irr"
          label="IZF"
          value={Format.signed_rate(@performance.irr, 2)}
          tone={sign(Format.signed_rate(@performance.irr, 2))}
          desc={join_meta([@per_year, "geldgewichtet"])}
          size={:sm}
        />
        <.stat
          id="drawdown"
          label="Max. Drawdown"
          value={Format.signed_rate(-@performance.drawdown.max, 2)}
          tone={sign(Format.signed_rate(-@performance.drawdown.max, 2))}
          size={:sm}
        >
          <:note>
            <.drawdown_days {@performance.drawdown} year={@performance.interval.last.year} />
          </:note>
        </.stat>
        <.stat
          id="volatility"
          label="Volatilität"
          value={@performance.volatility |> in_percent() |> Format.percent(2)}
          desc="nicht annualisiert"
          size={:sm}
        />
      </div>

      <%!-- Side by side only where the heatmap's months get room; else the heatmap under the
           breakdown. --%>
      <div class="mt-8 grid items-start gap-x-10 gap-y-8 2xl:grid-cols-[22rem_1fr]">
        <.breakdown breakdown={@performance.breakdown} interval={@performance.interval} />
        <.monthly_returns years={@performance.monthly_returns} />
      </div>
    </Layouts.depot>
    """
  end

  attr :breakdown, :map, required: true
  attr :interval, Date.Range, required: true

  # PP's performance calculation, from the initial to the final value; currency gains only when
  # there are any. The changes carry their sign, the two values none.
  defp breakdown(assigns) do
    ~H"""
    <section id="breakdown" aria-labelledby="breakdown-title">
      <.section_heading id="breakdown-title">Berechnung</.section_heading>
      <.description_list class="border-t border-base-content/10">
        <:item label={"Anfangswert am #{Format.date(@interval.first)}"} strong>
          <.amount value={@breakdown.initial_value} />
        </:item>
        <:item label="Unrealisierte Kursgewinne">
          <.amount value={@breakdown.capital_gains} signed />
        </:item>
        <:item label="Realisierte Kursgewinne">
          <.amount value={@breakdown.realized_capital_gains} signed />
        </:item>
        <:item label="Erträge"><.amount value={@breakdown.earnings} signed /></:item>
        <:item label="Gebühren"><.amount value={-@breakdown.fees} signed /></:item>
        <:item label="Steuern"><.amount value={-@breakdown.taxes} signed /></:item>
        <:item :if={@breakdown.currency_gains != 0} label="Währungsgewinne">
          <.amount value={@breakdown.currency_gains} signed />
        </:item>
        <:item label="Einlagen und Entnahmen">
          <.amount value={@breakdown.transfers} signed />
        </:item>
        <:item label={"Endwert am #{Format.date(@interval.last)}"} total>
          <.amount value={@breakdown.final_value} />
        </:item>
      </.description_list>
    </section>
    """
  end

  # Month abbreviation and name.
  @months Enum.map(1..12, &{Format.month_abbr(&1), Format.month_name(&1)})

  attr :years, :list, required: true

  # The TTWROR of every month since the first transaction as a heatmap, the newest year on top;
  # on a phone each year folds into two rows of six months.
  defp monthly_returns(assigns) do
    assigns = assign(assigns, months: @months)

    ~H"""
    <section id="monthly-returns" class="app-heatmap" aria-labelledby="monthly-returns-title">
      <.section_heading id="monthly-returns-title">Monatsrenditen</.section_heading>
      <table class="app-heatmap-table tabular-nums">
        <thead>
          <tr>
            <th scope="col"><span class="sr-only">Jahr</span></th>
            <th :for={{short, long} <- @months} scope="col">
              <abbr title={long}>{short}</abbr>
            </th>
            <th scope="col" class="app-heatmap-total">
              <abbr title="Jahr, aus den Monaten verkettet">Jahr</abbr>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={entry <- Enum.reverse(@years)} id={"monthly-returns-#{entry.year}"}>
            <th scope="row">{entry.year}</th>
            <.heat
              :for={{rate, {short, long}} <- Enum.zip(entry.months, @months)}
              rate={rate}
              places={1}
              scale={0.035}
              label={short}
              title={"#{long} #{entry.year}"}
            />
            <.heat
              rate={entry.total}
              places={2}
              scale={0.1}
              label="Jahr"
              title={"Jahr #{entry.year}"}
              class="app-heatmap-total"
            />
          </tr>
        </tbody>
      </table>
      <p class="pt-3 text-sm text-base-content/70">TTWROR je Monat in %, verkettet zum Jahr</p>
    </section>
    """
  end

  attr :rate, :float, required: true, doc: "nil for a month without returns"
  attr :places, :integer, required: true
  attr :scale, :float, required: true, doc: "the rate shown in the strongest colour"
  attr :label, :string, required: true, doc: "shown with the value on a phone"
  attr :title, :string, required: true
  attr :class, :string, default: nil

  defp heat(%{rate: nil} = assigns) do
    ~H"""
    <td class={@class} title={"#{@title}: keine Daten"}>
      <span class="app-heat app-heat-none" data-label={@label}>
        <span class="sr-only">keine Daten</span>
      </span>
    </td>
    """
  end

  defp heat(assigns) do
    rounded = assigns.rate |> in_percent() |> Decimal.round(assigns.places)

    assigns =
      assign(assigns,
        text: heat_text(rounded, assigns.places),
        tone: tone_class(rounded),
        strength: strength(assigns.rate, assigns.scale)
      )

    ~H"""
    <td class={@class} title={"#{@title}: #{@text}\u00A0%"}>
      <span class={["app-heat", @tone]} data-heat={@strength} data-label={@label}>
        {@text}
      </span>
    </td>
    """
  end

  # How strong a cell's colour is, in steps from 0 to 10 at `scale`; the root spreads the small
  # rates, which are the most.
  defp strength(rate, scale), do: round(:math.sqrt(min(abs(rate) / scale, 1.0)) * 10)

  # Zero as ±0,0, so that it lines up with the signed figures.
  defp heat_text(rounded, places) do
    if Decimal.eq?(rounded, 0),
      do: "±" <> Format.signed_number(rounded, places),
      else: Format.signed_number(rounded, places)
  end

  defp tone_class(rounded) do
    cond do
      Decimal.positive?(rounded) -> "app-heat-up"
      Decimal.negative?(rounded) -> "app-heat-down"
      true -> nil
    end
  end

  # The days after the reference day.
  defp days(interval), do: Format.days(Date.add(interval.first, 1), interval.last)

  defp portfolio_name(nil), do: "alle Depots und Konten"

  defp portfolio_name(%{reference_account_id: nil} = portfolio),
    do: Format.portfolio_name(portfolio)

  defp portfolio_name(portfolio), do: "#{Format.portfolio_name(portfolio)} mit Referenzkonto"

  attr :max, :float, required: true
  attr :from, Date, required: true
  attr :to, Date, required: true
  attr :year, :integer, required: true, doc: "left out of the days when they are in it"

  defp drawdown_days(%{max: max} = assigns) when max == 0, do: ~H"kein Rückgang"

  defp drawdown_days(assigns) do
    ~H"""
    <span class="text-nowrap" title={Format.date_span(@from, @to)}>
      {Format.date_span(@from, @to, @from.year != @year or @to.year != @year)}
    </span><.meta_sep /><span class="text-nowrap">{days_count(Date.diff(@to, @from))}</span>
    """
  end

  defp days_count(1), do: "1 Tag"
  defp days_count(days), do: "#{days} Tage"

  # A rate, a fraction, in percent.
  defp in_percent(rate), do: Decimal.from_float(rate * 100)

  defp performance_path(period, portfolio) do
    query =
      Enum.reject(
        [period: Periods.param(@periods, period), portfolio: portfolio_id(portfolio)],
        &is_nil(elem(&1, 1))
      )

    ~p"/depot/performance?#{query}"
  end

  defp portfolio_id(%{id: id}), do: id
  defp portfolio_id(id), do: id

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Performance")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(
      period: Periods.parse(@periods, params["period"], @default_period),
      portfolio_id: parse_id(params["portfolio"])
    )
    |> load_performance()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_performance(socket)}

  defp load_performance(socket) do
    %{current_scope: scope, period: period, portfolio_id: portfolio_id} = socket.assigns

    assign(
      socket,
      :performance,
      Portfolios.performance(scope, period, portfolio_id, LocalTime.today())
    )
  end
end
