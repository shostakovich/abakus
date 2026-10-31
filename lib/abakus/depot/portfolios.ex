defmodule Abakus.Depot.Portfolios do
  @moduledoc """
  Portfolios and their transactions, each of one user, the transactions the user books with their
  receipts, and what the screens show of them: net worth, the overview, the holdings, the dividends,
  the performance, the sidebar and the user's holding of a security, computed from the transactions on
  every request. Their accounts are the user's accounts in the Ledger, which holds their balances.
  """

  import Ecto.Query, warn: false

  alias Abakus.Depot.{
    Allocation,
    CashSide,
    Costs,
    Distributions,
    Dividends,
    Performance,
    Period,
    PriceChart,
    Securities,
    Settings,
    Taxonomies,
    Valuation
  }

  alias Abakus.Depot.Allocation.Classifications
  alias Abakus.Depot.Performance.Breakdown

  alias Abakus.Depot.Portfolios.{
    Portfolio,
    PortfolioForm,
    Receipt,
    Transaction,
    TransactionForm,
    TransactionUnit
  }

  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation.{Filter, Market, PurchaseValue}
  alias Abakus.{ExchangeRates, Ledger, Repo, Sync}
  alias Abakus.Users.{Scope, User}

  @doc "Whether the user has a portfolio, which opens the Depot to them."
  def any?(%User{} = user), do: Repo.exists?(from p in Portfolio, where: p.user_id == ^user.id)

  def list_portfolios(%Scope{} = scope),
    do: Repo.all(from p in Portfolio, where: p.user_id == ^scope.user.id, order_by: p.name)

  @doc "The form of a new portfolio with its Verrechnungskonto."
  def change_new_portfolio(attrs \\ %{}), do: PortfolioForm.changeset(%PortfolioForm{}, attrs)

  @doc """
  Creates a portfolio of the user with a new tracking account in the Ledger as its Verrechnungskonto, which its
  purchases, sales and dividends settle against and which is its cash.
  """
  def create_portfolio(%Scope{} = scope, attrs) do
    with {:ok, form} <- Ecto.Changeset.apply_action(change_new_portfolio(attrs), :insert) do
      Sync.write(fn -> insert_portfolio(scope, form) end)
    end
  end

  defp insert_portfolio(scope, form) do
    with {:ok, account} <-
           Ledger.create_account(scope, %{name: form.account_name, kind: :tracking}) do
      {:ok,
       Repo.insert!(%Portfolio{
         user_id: scope.user.id,
         name: form.name,
         reference_account_id: account.id
       })}
    end
  end

  @doc "The user's portfolios with their Verrechnungskonto, the active ones first, each by name, for their settings."
  def list_portfolios_with_accounts(%Scope{} = scope) do
    Repo.all(
      from p in Portfolio,
        where: p.user_id == ^scope.user.id,
        order_by: [p.retired, p.name, p.id],
        preload: :reference_account
    )
  end

  @doc """
  The accounts a portfolio of the user may take as its Verrechnungskonto, in the Ledger's order: as `accounts` the one
  it has and their open accounts but the shared-expenses account and another portfolio's cash. `owners` gives the name
  of the portfolio whose cash a tracking account is, by account id, the portfolio's own left out; `waiting_ids` are the
  tracking accounts with transactions waiting for approval or a match decision, which no register shows once they are
  a portfolio's cash.
  """
  def account_choices(%Scope{} = scope, %Portfolio{} = portfolio) do
    names = Map.new(list_portfolios(scope), &{&1.id, &1.name})

    owners =
      for {account_id, id} <- cash_account_portfolios(scope),
          id != portfolio.id,
          into: %{},
          do: {account_id, names[id]}

    accounts = Ledger.list_accounts(scope)

    tracking =
      for a <- accounts, not Ledger.Account.budget_account?(a), into: MapSet.new(), do: a.id

    %{
      accounts:
        Enum.filter(
          accounts,
          &(&1.id == portfolio.reference_account_id or
              (Ledger.Account.takes_entries?(&1) and not Map.has_key?(owners, &1.id)))
        ),
      owners: owners,
      waiting_ids:
        for(
          {id, %{unapproved: unapproved}} <- Ledger.balances(scope),
          unapproved > 0 and id in tracking,
          into: MapSet.new(),
          do: id
        )
    }
  end

  @doc """
  The form of a portfolio's depot number and Verrechnungskonto, checked against `choices`, see `account_choices/2`.
  """
  def change_portfolio(%Scope{} = scope, %Portfolio{} = portfolio, attrs \\ %{}, choices \\ nil) do
    choices = choices || account_choices(scope, portfolio)

    Portfolio.changeset(portfolio, attrs, %{
      taken_by: &depot_number_taken_by(scope, portfolio, &1),
      account_ids: MapSet.new(choices.accounts, & &1.id),
      owners: choices.owners,
      waiting_ids: choices.waiting_ids
    })
  end

  @doc """
  Saves the form of a portfolio of the user, see `change_portfolio/4`; no two of their portfolios may share a depot
  number's digits, nor a tracking account as Verrechnungskonto. What derives from the account follows on the next
  read; the Depot's transactions keep the accounts they were booked on.
  """
  def update_portfolio(%Scope{} = scope, %Portfolio{user_id: user_id} = portfolio, attrs)
      when user_id == scope.user.id,
      do: Repo.transact(fn -> scope |> change_portfolio(portfolio, attrs) |> Repo.update() end)

  defp depot_number_taken_by(scope, portfolio, digits) do
    Repo.all(
      from p in Portfolio,
        where:
          p.user_id == ^scope.user.id and p.id != ^portfolio.id and not is_nil(p.depot_number)
    )
    |> Enum.find_value(&(Portfolio.digits(&1.depot_number) == digits && &1.name))
  end

  @doc """
  The user's accounts the Depot uses, by name: the Verrechnungskonten of their portfolios and those their transactions
  book on.
  """
  def list_accounts(%Scope{user: %User{id: user_id}}) do
    ids =
      Repo.all(
        from t in Transaction,
          where: t.user_id == ^user_id,
          select: [t.account_id, t.other_account_id]
      ) ++
        Repo.all(
          from p in Portfolio, where: p.user_id == ^user_id, select: [p.reference_account_id]
        )

    ids = ids |> List.flatten() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Repo.all(
      from a in Ledger.Account,
        where: a.user_id == ^user_id and a.id in ^ids,
        order_by: [a.name, a.id]
    )
  end

  @doc """
  The user's accounts whose money is the Depot's, as `%{account_id => portfolio_id}`: a tracking account as a
  portfolio's Verrechnungskonto is its cash at the broker, the portfolio active or retired. The Depot counts it toward
  that portfolio; the budget's registers, account pickers and file import leave it out. A budget account as
  Verrechnungskonto stays the budget's.
  """
  def cash_account_portfolios(%Scope{} = scope) do
    Repo.all(
      from p in Portfolio,
        join: a in assoc(p, :reference_account),
        where: p.user_id == ^scope.user.id and a.kind == :tracking,
        select: {a.id, p.id}
    )
    |> Map.new()
  end

  defp cash_of(scope, %Portfolio{id: id}),
    do: for({account_id, ^id} <- cash_account_portfolios(scope), do: account_id)

  def list_transactions(%Scope{} = scope) do
    Repo.all(
      from t in Transaction,
        where: t.user_id == ^scope.user.id,
        order_by: [t.date_time, t.id],
        preload: :units
    )
  end

  @doc """
  The user's net worth on each of `dates` as `%{date => cents}`: the value of all holdings plus
  the account balances, in euros.
  """
  def net_worth(%Scope{} = scope, dates) do
    transactions = list_transactions(scope)
    market = load_market(transactions, Enum.min(dates, Date))

    transactions
    |> Valuation.history(market, dates)
    |> Map.new(&{&1.date, &1.net_worth})
  end

  @doc """
  The value of all the user's holdings on each of `dates` as `%{date => cents}`, in euros, without the accounts.
  """
  def holdings_value(%Scope{} = scope, dates) do
    transactions = list_transactions(scope)
    market = load_market(transactions, Enum.min(dates, Date))

    transactions
    |> Valuation.history(market, dates, Filter.holdings())
    |> Map.new(&{&1.date, &1.net_worth})
  end

  @doc """
  What the overview shows for `period` up to `today`, from one load of the user's transactions,
  amounts in euro cents:

  - `net_worth` today and `net_worth_yesterday`
  - `first_day`: the day of the first transaction, nil without any
  - `chart`: net worth, invested capital and the value of the shadow portfolio in the benchmark
    (`benchmark`, nil without one) on the days of the period a chart shows, see
    `Performance.shadow_portfolio/4`
  - `ttwror` and `irr` of all portfolios and accounts over the period, see `Performance`
  - `benchmark`: the user's benchmark as `%{security, ttwror}` over the same interval, see
    `Performance.benchmark_ttwror/3`; nil when they picked none
  - `dividends`: this year's up to `today`, before taxes and fees
  - `portfolios`: the portfolios by name, retired ones only while they hold shares, each with
    `cash`, the balance of its accounts as the holdings screen groups them for all portfolios
    (nil without any), the number of
    `securities` held, the `value` of the securities and their `ttwror` since 1 January, as PP
    figures a portfolio without its cash.
  """
  def overview(%Scope{} = scope, period, today) do
    transactions = list_transactions(scope)
    first_day = first_transaction_day(transactions)
    interval = Period.interval(period, today, first_day)
    year = Period.interval(:year_to_date, today, first_day)
    first = Enum.min([interval.first, year.first], Date)
    benchmark = get_benchmark(scope)

    market = load_market(transactions, first, benchmark: benchmark)
    index = Performance.index(transactions, market, Filter.all(), interval)
    [yesterday, today_point] = Enum.take(index.days, -2)
    range = Period.range(period, today, first_day)

    %{
      net_worth: today_point.value,
      net_worth_yesterday: yesterday.value,
      first_day: first_day,
      chart: chart(index, range, shadow_portfolio(benchmark, index, market, range.first)),
      ttwror: Performance.ttwror(index),
      irr: Performance.irr(index),
      benchmark: benchmark(benchmark, index, market),
      dividends: Valuation.gross_dividends(transactions, year_to_date(today)),
      portfolios: portfolios_overview(scope, transactions, market, year)
    }
  end

  @doc """
  What the performance screen shows for `period` up to `today`, of all portfolios and accounts or
  of the portfolio with `portfolio_id` and its cash, see `cash_account_portfolios/1`:

  - `portfolios`: the portfolios to choose from, as the holdings screen lists them
  - `portfolio`: the chosen one of them, nil for all
  - `interval`: the days of the period, the first the reference day, see `Period.interval/3`
  - `ttwror`, `ttwror_per_year`, `irr`, `drawdown` and `volatility`, see `Performance`
  - `benchmark`: as in `overview/3`, over the interval
  - `breakdown`: where the change in value came from, see `Performance.Breakdown`
  - `monthly_returns`: the TTWROR of every month and year since the first transaction, whatever
    the period, see `Performance.monthly_returns/1`
  """
  def performance(%Scope{} = scope, period, portfolio_id, today) do
    transactions = list_transactions(scope)
    portfolios = choosable_portfolios(scope, Valuation.holdings(transactions, today))
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))
    first_day = first_transaction_day(transactions)
    interval = Period.interval(period, today, first_day)
    all_time = Period.interval(:max, today, first_day)
    benchmark = get_benchmark(scope)

    market = load_market(transactions, all_time.first, benchmark: benchmark)
    filter = performance_filter(scope, portfolio, transactions)
    index = Performance.index(transactions, market, filter, interval)

    all_time_index =
      if interval == all_time,
        do: index,
        else: Performance.index(transactions, market, filter, all_time)

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      interval: interval,
      ttwror: Performance.ttwror(index),
      ttwror_per_year: Performance.ttwror_per_year(index),
      benchmark: benchmark(benchmark, index, market),
      irr: Performance.irr(index),
      drawdown: Performance.drawdown(index),
      volatility: Performance.volatility(index),
      breakdown: Breakdown.of(transactions, market, filter, index),
      monthly_returns: Performance.monthly_returns(all_time_index)
    }
  end

  defp get_benchmark(scope) do
    if id = Settings.benchmark_id(scope), do: Securities.get_security(scope, id)
  end

  defp benchmark(nil, _index, _market), do: nil

  defp benchmark(security, index, market),
    do: %{security: security, ttwror: Performance.benchmark_ttwror(index, market, security.id)}

  defp performance_filter(_scope, nil, _transactions), do: Filter.all()

  defp performance_filter(scope, portfolio, transactions),
    do: Filter.new([portfolio], cash_of(scope, portfolio), transactions)

  defp first_transaction_day([first | _]), do: NaiveDateTime.to_date(first.date_time)
  defp first_transaction_day([]), do: nil

  defp chart(%Performance{days: days}, range, shadow_portfolio) do
    chart_days = range |> Period.chart_days() |> MapSet.new()

    for day <- days,
        MapSet.member?(chart_days, day.date),
        do: %{
          date: day.date,
          net_worth: day.value,
          invested_capital: day.invested_capital,
          benchmark: shadow_portfolio[day.date]
        }
  end

  defp shadow_portfolio(nil, _index, _market, _first_day), do: %{}

  defp shadow_portfolio(security, index, market, first_day),
    do: Performance.shadow_portfolio(index, market, security.id, first_day)

  defp year_to_date(%Date{year: year} = today), do: Date.range(Date.new!(year, 1, 1), today)

  defp portfolios_overview(scope, transactions, market, %Date.Range{last: today} = year) do
    holdings = Valuation.holdings(transactions, today)
    portfolios = choosable_portfolios(scope, holdings)

    rows = %{
      holdings: value_rows(holdings, market, today),
      accounts: account_rows(scope, today)
    }

    for %{portfolio: %Portfolio{} = portfolio} = group <- holding_groups(portfolios, nil, rows) do
      # The securities alone, with the dividends on the Verrechnungskonto; purchases and sales are money in and out.
      filter = Filter.new([portfolio], [], transactions)
      index = Performance.index(transactions, market, filter, year)

      %{
        portfolio: portfolio,
        cash: if(group.accounts != [], do: Enum.sum_by(group.accounts, & &1.value)),
        securities: length(group.holdings),
        value: List.last(index.days).value,
        ttwror: Performance.ttwror(index)
      }
    end
  end

  @doc "The portfolios the screens offer by name on `today`, retired ones only while they hold shares."
  def shown_portfolios(%Scope{} = scope, %Date{} = today),
    do: choosable_portfolios(scope, Valuation.holdings(list_transactions(scope), today))

  defp choosable_portfolios(scope, holdings) do
    held = MapSet.new(holdings, & &1.portfolio_id)
    Enum.filter(list_portfolios(scope), &(not &1.retired or MapSet.member?(held, &1.id)))
  end

  @doc """
  What the holdings screen shows on `today` for all portfolios, or for the one with
  `portfolio_id`; amounts in euro cents, prices × 10⁸ in the security's currency:

  - `portfolios`: the portfolios to choose from by name, retired ones only while they hold shares
  - `portfolio`: the chosen one of them, nil for all
  - `groups`: each portfolio shown with its `holdings` by value and in `accounts` its cash, see
    `cash_account_portfolios/1`; for all portfolios, the accounts of no portfolio shown follow in a
    group without portfolio. Each group has the `value` of its rows, the `purchase_value` and `gain`
    of its holdings and the `cash` of its accounts.
  - `total`: `value`, `purchase_value` and `gain` of the groups shown, the `dividends` of their
    holdings and the `securities_value` they make up
  - `net_worth`: the value of all holdings and accounts, of which each row shows its share
  - `costs`: what the securities shown cost a year, see `Costs.of/1`; accounts hold no funds
  - `allocation`: the regions and sectors of the securities shown, see `Allocation.of/2`, and in
    `taxonomies` the allocation of the securities and accounts shown into each of the user's
    taxonomies by name, see `Classifications.of/3`, those without value shown in them left out

  A holding has its `security`, `shares`, `price`, `value`, `purchase_value`, `gain` and the gross
  `dividends` of the next 12 months, its part of those of its security (see `Dividends.upcoming/4`)
  by shares; an account has its `value`, its balance in the Ledger. Closed accounts are left out once they are empty,
  budget accounts always.
  """
  def holdings(%Scope{} = scope, portfolio_id, today) do
    transactions = list_transactions(scope)
    stored = stored_dividends(transactions)
    market = load_market(transactions, today, dividends: stored)

    holdings = Valuation.holdings(transactions, today)
    portfolios = choosable_portfolios(scope, holdings)
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))
    upcoming = Dividends.upcoming(transactions, stored, market, today)

    rows = %{
      holdings: holdings |> holding_rows(transactions, market, today) |> with_dividends(upcoming),
      accounts: account_rows(scope, today)
    }

    groups = portfolios |> holding_groups(portfolio, rows) |> Enum.map(&with_gains/1)
    shown = Enum.flat_map(groups, & &1.holdings)
    shown_accounts = Enum.flat_map(groups, & &1.accounts)

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      groups: groups,
      total: groups |> totals() |> Map.merge(dividend_totals(shown)),
      net_worth: Enum.sum_by(rows.holdings ++ rows.accounts, & &1.value),
      costs: Costs.of(shown),
      allocation: allocation(scope, shown, shown_accounts)
    }
  end

  defp with_dividends(rows, upcoming) do
    gross = upcoming |> Enum.group_by(& &1.security.id, & &1.gross) |> Map.new(&sum_values/1)
    shares = rows |> Enum.group_by(& &1.security.id, & &1.shares) |> Map.new(&sum_values/1)

    Enum.map(rows, fn row ->
      id = row.security.id
      Map.put(row, :dividends, rounded_part(Map.get(gross, id, 0), row.shares, shares[id]))
    end)
  end

  defp sum_values({key, values}), do: {key, Enum.sum(values)}

  defp rounded_part(cents, part, whole) when whole > 0,
    do: div(cents * part * 2 + whole, whole * 2)

  defp rounded_part(_cents, _part, _whole), do: 0

  defp dividend_totals(holdings) do
    %{
      dividends: Enum.sum_by(holdings, & &1.dividends),
      securities_value: Enum.sum_by(holdings, & &1.value)
    }
  end

  defp allocation(scope, holdings, accounts) do
    compositions =
      holdings |> Enum.map(& &1.security.id) |> Enum.uniq() |> Securities.list_compositions()

    taxonomies =
      for taxonomy <- Taxonomies.list_taxonomies(scope),
          allocation = Classifications.of(taxonomy, holdings, accounts),
          allocation.classifications != [],
          do: allocation

    holdings |> Allocation.of(compositions) |> Map.put(:taxonomies, taxonomies)
  end

  @doc """
  What the dividend screen shows on `today` for all portfolios, or for the one with `portfolio_id`
  and its cash; amounts in euro cents:

  - `portfolios` and `portfolio`: as in `holdings/3`
  - `received`: every dividend booked, newest first, see `Dividends.received/2`
  - `years`: the dividends per month and year since the first, see `Dividends.by_year/2`
  - `this_year` up to `today` and `last_year` in all, each as `gross` and `net`
  - `upcoming`: the dividends announced or forecast for the coming months, see
    `Dividends.upcoming/4`, with their `total` and per month in `months`, see
    `Dividends.by_coming_month/2`
  - `value` and `purchase_value` of the holdings shown today, for the yields
  """
  def dividends(%Scope{} = scope, portfolio_id, %Date{} = today) do
    transactions = list_transactions(scope)
    stored = stored_dividends(transactions)

    market = load_market(transactions, today, dividends: stored)

    held = Valuation.holdings(transactions, today)
    portfolios = choosable_portfolios(scope, held)
    portfolio = Enum.find(portfolios, &(&1.id == portfolio_id))

    received =
      transactions |> of_portfolio(portfolio, scope, transactions) |> Dividends.received(market)

    upcoming =
      Dividends.upcoming(transactions, stored, market, today,
        received: received,
        portfolio_id: portfolio && portfolio.id
      )

    holdings =
      held
      |> Enum.filter(&(portfolio == nil or &1.portfolio_id == portfolio.id))
      |> holding_rows(transactions, market, today)

    last_year = Date.range(Date.new!(today.year - 1, 1, 1), Date.new!(today.year - 1, 12, 31))

    %{
      portfolios: portfolios,
      portfolio: portfolio,
      received: received,
      years: Dividends.by_year(received, today),
      this_year: Dividends.total(received, year_to_date(today)),
      last_year: Dividends.total(received, last_year),
      upcoming: upcoming,
      total: Dividends.total(upcoming),
      months: Dividends.by_coming_month(upcoming, today),
      value: Enum.sum_by(holdings, & &1.value),
      purchase_value: Enum.sum_by(holdings, & &1.purchase_value)
    }
  end

  @doc """
  The dividends the overview expects after `today`, gross, see `Dividends.upcoming/4`:

  - `upcoming`: all of them, by pay date
  - `rest_of_year`: the total of those paid this year
  - `next_three_months`: those of today's month and the next two
  """
  def upcoming_dividends(%Scope{} = scope, %Date{} = today) do
    transactions = list_transactions(scope)
    stored = stored_dividends(transactions)

    market = load_market(transactions, today, dividends: stored)

    upcoming = Dividends.upcoming(transactions, stored, market, today)
    three_months = today |> Date.beginning_of_month() |> Date.shift(month: 3)

    %{
      upcoming: upcoming,
      rest_of_year:
        upcoming |> Enum.filter(&(&1.pay_date.year == today.year)) |> Enum.sum_by(& &1.gross),
      next_three_months: Enum.filter(upcoming, &Date.before?(&1.pay_date, three_months))
    }
  end

  defp stored_dividends(transactions) do
    transactions
    |> Enum.map(& &1.security_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Securities.list_divvy_diary_dividends()
  end

  @doc """
  What the security page shows of `security` on `today`; amounts in euro cents, prices × 10⁸ in
  the security's currency, shares × 10⁸. The security and its prices are shared by all users,
  the holdings and trades are the user's:

  - `price` today and `price_yesterday`, nil without any price
  - `chart`: see `PriceChart.of/4`, over the days of `period` from the first price or trade on
  - `holdings`: the holdings of it by portfolio name, each with its `portfolio`, `shares`,
    `value`, `purchase_value` and `gain`
  - `total`: the `shares`, `value`, `purchase_value` and `gain` of all holdings
  - `costs_per_year` of the holdings, see `Costs.of/1`
  - `distributions`: from the user's dividends, see `Distributions.of/1`
  - `upcoming`: the dividends expected of it, see `Dividends.upcoming/4`
  """
  def security(%Scope{} = scope, %Security{} = security, period, today) do
    transactions = list_transactions_of(scope, security)
    closes = scope |> Securities.list_prices(security) |> Enum.map(&{&1.date, &1.close})
    stored = Securities.list_divvy_diary_dividends([security.id])
    market = security_market(security, closes, stored, today)
    holdings = security_holdings(scope, transactions, market, today)
    range = Period.range(period, today, first_price_or_trade(security, closes, transactions))

    %{
      price: Market.price(market, security.id, today),
      price_yesterday: Market.price(market, security.id, Date.add(today, -1)),
      chart: PriceChart.of(security, closes, transactions, range),
      holdings: holdings,
      total: holdings |> totals() |> Map.put(:shares, Enum.sum_by(holdings, & &1.shares)),
      costs_per_year: Costs.of(holdings).per_year,
      distributions: Distributions.of(transactions),
      upcoming: Dividends.upcoming(transactions, stored, market, today)
    }
  end

  defp list_transactions_of(scope, %Security{id: security_id}) do
    Repo.all(
      from t in Transaction,
        where: t.user_id == ^scope.user.id and t.security_id == ^security_id,
        order_by: [t.date_time, t.id],
        preload: :units
    )
  end

  defp security_market(security, closes, dividends, today) do
    currencies = [security | dividends] |> Enum.map(& &1.currency) |> Market.rate_currencies()

    Market.new(
      [security],
      Enum.map(closes, fn {date, close} -> {security.id, date, close} end),
      ExchangeRates.list_rates_since(currencies, today)
    )
  end

  defp security_holdings(scope, transactions, market, today) do
    portfolios = Map.new(list_portfolios(scope), &{&1.id, &1})

    transactions
    |> Valuation.holdings(today)
    |> holding_rows(transactions, market, today)
    |> Enum.map(&Map.put(&1, :portfolio, portfolios[&1.portfolio_id]))
    |> Enum.sort_by(& &1.portfolio.name)
  end

  # Closes and transactions come in order of date; the latest quote may be all there is.
  defp first_price_or_trade(security, closes, transactions) do
    [
      Enum.map(Enum.take(closes, 1), &elem(&1, 0)),
      List.wrap(security.latest_date),
      Enum.map(Enum.take(transactions, 1), &NaiveDateTime.to_date(&1.date_time))
    ]
    |> Enum.concat()
    |> Enum.min(Date, fn -> nil end)
  end

  @doc """
  What the sidebar shows on `today`: the active portfolios by name, each with its `value` in euro
  cents, its securities valued as the holdings screen values all portfolios plus the balances of its
  cash in the Ledger; nothing retired, whatever it still holds.
  """
  def sidebar(%Scope{} = scope, today) do
    transactions = list_transactions(scope)
    market = load_market(transactions, today)
    holdings = Valuation.holdings(transactions, today)
    balances = Ledger.balances_through(scope, today)

    cash =
      scope
      |> cash_account_portfolios()
      |> Enum.group_by(&elem(&1, 1), &Map.get(balances, elem(&1, 0), 0))
      |> Map.new(&sum_values/1)

    portfolios =
      for portfolio <- list_portfolios(scope), not portfolio.retired do
        securities =
          holdings
          |> Enum.filter(&(&1.portfolio_id == portfolio.id))
          |> Enum.sum_by(&Valuation.value(&1, market, today))

        %{portfolio: portfolio, value: securities + Map.get(cash, portfolio.id, 0)}
      end

    %{portfolios: portfolios}
  end

  defp value_rows(holdings, market, today) do
    for holding <- holdings,
        do: %{portfolio_id: holding.portfolio_id, value: Valuation.value(holding, market, today)}
  end

  defp holding_rows(holdings, transactions, market, today) do
    purchase_values = PurchaseValue.by_holding(transactions, today)

    for holding <- holdings do
      value = Valuation.value(holding, market, today)
      purchase_value = Map.get(purchase_values, {holding.portfolio_id, holding.security_id}, 0)

      %{
        portfolio_id: holding.portfolio_id,
        security: Market.security(market, holding.security_id),
        shares: holding.shares,
        price: Valuation.price(holding, market, today),
        value: value,
        purchase_value: purchase_value,
        gain: value - purchase_value
      }
    end
  end

  defp account_rows(%Scope{} = scope, today) do
    balances = Ledger.balances_through(scope, today)
    cash_of = cash_account_portfolios(scope)

    for account <- list_accounts(scope),
        not Ledger.Account.budget_account?(account),
        balance = Map.get(balances, account.id, 0),
        not account.closed or balance != 0,
        do: %{account: account, value: balance, cash_of: cash_of[account.id]}
  end

  defp holding_groups(_portfolios, %Portfolio{} = portfolio, rows),
    do: [holding_group(portfolio, rows)]

  defp holding_groups(portfolios, nil, rows) do
    shown = MapSet.new(portfolios, & &1.id)
    groups = Enum.map(portfolios, &holding_group(&1, rows))

    case Enum.reject(rows.accounts, &MapSet.member?(shown, &1.cash_of)) do
      [] -> groups
      accounts -> groups ++ [group(nil, [], accounts)]
    end
  end

  defp holding_group(portfolio, rows) do
    group(
      portfolio,
      Enum.filter(rows.holdings, &(&1.portfolio_id == portfolio.id)),
      Enum.filter(rows.accounts, &(&1.cash_of == portfolio.id))
    )
  end

  defp group(portfolio, holdings, accounts) do
    %{
      portfolio: portfolio,
      holdings: holdings,
      accounts: accounts,
      value: Enum.sum_by(holdings ++ accounts, & &1.value)
    }
  end

  defp with_gains(%{holdings: holdings} = group) do
    Map.merge(group, %{
      cash: Enum.sum_by(group.accounts, & &1.value),
      holdings: Enum.sort_by(holdings, &{-&1.value, &1.security.name}),
      purchase_value: Enum.sum_by(holdings, & &1.purchase_value),
      gain: Enum.sum_by(holdings, & &1.gain)
    })
  end

  defp totals(rows) do
    %{
      value: Enum.sum_by(rows, & &1.value),
      purchase_value: Enum.sum_by(rows, & &1.purchase_value),
      gain: Enum.sum_by(rows, & &1.gain)
    }
  end

  defp load_market(transactions, date, opts \\ []) do
    benchmark = opts[:benchmark]
    dividends = Keyword.get(opts, :dividends, [])

    security_ids =
      transactions
      |> Enum.map(& &1.security_id)
      |> Enum.concat(List.wrap(benchmark && benchmark.id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    securities = Securities.list_securities_by_id(security_ids)

    currencies = (securities ++ dividends) |> Enum.map(& &1.currency) |> Market.rate_currencies()

    Market.new(
      securities,
      Securities.list_closes_since(security_ids, date),
      ExchangeRates.list_rates_since(currencies, date)
    )
  end

  @filters %{
    trades: [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer],
    earnings: [:dividend, :interest],
    account: [
      :deposit,
      :removal,
      :cash_transfer,
      :interest_charge,
      :tax,
      :tax_refund,
      :fee,
      :fee_refund
    ]
  }

  @transaction_preloads [
    :units,
    :security,
    :portfolio,
    :account,
    :other_portfolio,
    :other_account,
    :receipt
  ]

  @doc """
  The user's transactions grouped by month, newest first, as `{first day of month, transactions}`;
  `filter` is nil for all, `:trades`, `:earnings` or `:account`; `portfolio` nil for all
  portfolios, or one of them for its transactions, those of its cash and its securities' dividends, taxes and fees on
  its Verrechnungskonto.
  """
  def transactions_by_month(%Scope{} = scope, filter \\ nil, portfolio \\ nil) do
    from(t in Transaction,
      where: t.user_id == ^scope.user.id,
      order_by: [desc: t.date_time, desc: t.id],
      preload: ^@transaction_preloads
    )
    |> where_filter(filter)
    |> Repo.all()
    |> of_portfolio(portfolio, scope)
    |> Enum.chunk_by(&month_of/1)
    |> Enum.map(&{month_of(hd(&1)), &1})
  end

  defp of_portfolio(transactions, nil, _scope), do: transactions

  defp of_portfolio(transactions, portfolio, scope),
    do: of_portfolio(transactions, portfolio, scope, list_transactions(scope))

  # `all` tells which securities the portfolio held.
  defp of_portfolio(transactions, nil, _scope, _all), do: transactions

  defp of_portfolio(transactions, portfolio, scope, all) do
    filter = Filter.new([portfolio], cash_of(scope, portfolio), all)
    Enum.filter(transactions, &Filter.concerns?(filter, &1))
  end

  defp where_filter(query, nil), do: query
  defp where_filter(query, filter), do: where(query, [t], t.type in ^Map.fetch!(@filters, filter))

  defp month_of(%Transaction{date_time: date_time}),
    do: date_time |> NaiveDateTime.to_date() |> Date.beginning_of_month()

  @doc """
  A transaction of the user with what the transactions screen shows of it, nil for an unknown one
  or another user's.
  """
  def get_transaction(%Scope{} = scope, id) do
    Repo.one(
      from t in Transaction,
        where: t.id == ^id and t.user_id == ^scope.user.id,
        preload: ^@transaction_preloads
    )
  end

  @doc "A receipt of the user, nil for an unknown one or another user's."
  def get_receipt(%Scope{} = scope, id),
    do: Repo.get_by(Receipt, id: id, user_id: scope.user.id)

  @doc """
  What the transaction form offers: the user's portfolios by name, without retired ones, and their accounts in the
  Ledger in their order, without closed ones and those another area feeds, each but those of the transaction being
  edited; and all securities.
  """
  def transaction_choices(%Scope{} = scope, editing \\ nil) do
    %{
      portfolios:
        Enum.filter(
          list_portfolios(scope),
          &(not &1.retired or &1.id == (editing && editing.portfolio_id))
        ),
      accounts:
        Enum.filter(
          Ledger.list_accounts(scope),
          &(Ledger.Account.takes_entries?(&1) or &1.id == (editing && editing.account_id))
        ),
      securities: Securities.list_securities(scope)
    }
  end

  @doc """
  The transaction form with `attrs`, checked against `choices`, see `transaction_choices/2`. A sale
  may not exceed the holding on its day or later, which leaves out the transaction being edited.
  """
  def change_transaction_form(%Scope{} = scope, choices, attrs \\ %{}, editing \\ nil),
    do: TransactionForm.changeset(%TransactionForm{}, attrs, checks(scope, choices, editing))

  defp checks(scope, choices, editing) do
    %{
      portfolio_ids: MapSet.new(choices.portfolios, & &1.id),
      account_ids: MapSet.new(choices.accounts, & &1.id),
      security_ids: MapSet.new(choices.securities, & &1.id),
      held_shares: &held_shares(scope, &1, &2, &3, editing)
    }
  end

  @doc """
  The fewest shares × 10⁸ of a security a portfolio of the user holds from the end of `date` on,
  without the transaction `except` if given and with the transactions `extra`.
  """
  def held_shares(%Scope{} = scope, portfolio_id, security_id, date, except \\ nil, extra \\ []) do
    transactions =
      scope
      |> list_transactions_of(%Security{id: security_id})
      |> Enum.reject(&(except && &1.id == except.id))
      |> Enum.concat(Enum.filter(extra, &(&1.security_id == security_id)))

    later =
      for t <- transactions,
          day = NaiveDateTime.to_date(t.date_time),
          Date.after?(day, date),
          do: day

    [date | later]
    |> Enum.uniq()
    |> Enum.map(fn day ->
      transactions
      |> Valuation.holdings(day)
      |> Enum.find_value(0, &(&1.portfolio_id == portfolio_id && &1.shares))
    end)
    |> Enum.min()
  end

  defp keeps_holding?(scope, %Transaction{} = t, replacement) do
    date = NaiveDateTime.to_date(t.date_time)

    Enum.all?(
      receiving_portfolio_ids(t),
      &(held_shares(scope, &1, t.security_id, date, t, List.wrap(replacement)) >= 0)
    )
  end

  defp receiving_portfolio_ids(%Transaction{type: type} = t)
       when type in [:buy, :inbound_delivery],
       do: [t.portfolio_id]

  defp receiving_portfolio_ids(%Transaction{type: :security_transfer} = t),
    do: [t.other_portfolio_id]

  defp receiving_portfolio_ids(_transaction), do: []

  @doc """
  Books the transaction form with `attrs` and returns the booked transactions: one, or a dividend
  and its removal. `receipt` is an optional PDF as `{path, filename}`, attached to the first of
  them, which counts as booked manually; or a ready receipt of the inbox, which the first is
  booked from and which is booked with it, `{:error, :gone}` if it no longer waits.
  """
  def book_transaction(scope, choices, attrs, receipt \\ nil)

  def book_transaction(%Scope{} = scope, choices, attrs, %Receipt{} = receipt) do
    changeset = change_transaction_form(scope, choices, attrs)

    Sync.write(fn ->
      with {:ok, form} <- Ecto.Changeset.apply_action(changeset, :insert),
           :ok <- claim_ready_receipt(scope, receipt) do
        insert_transactions(scope, form, %{receipt_id: receipt.id, source: :receipt})
      end
    end)
  end

  def book_transaction(%Scope{} = scope, choices, attrs, receipt) do
    changeset = change_transaction_form(scope, choices, attrs)

    transact_with_receipt(receipt, fn ->
      with {:ok, form} <- Ecto.Changeset.apply_action(changeset, :insert),
           {:ok, receipt_id} <- store_receipt(scope, receipt, changeset) do
        insert_transactions(scope, form, %{receipt_id: receipt_id})
      end
    end)
  end

  defp insert_transactions(scope, form, first_attrs) do
    [first | rest] = TransactionForm.to_transactions(form)

    transactions = [
      insert_transaction(scope, Map.merge(first, first_attrs))
      | Enum.map(rest, &insert_transaction(scope, &1))
    ]

    with :ok <- CashSide.sync(scope), do: {:ok, transactions}
  end

  defp claim_ready_receipt(scope, receipt) do
    query =
      from r in Receipt,
        where: r.id == ^receipt.id and r.user_id == ^scope.user.id and r.status == :ready

    case Repo.update_all(query, set: [status: :booked, updated_at: DateTime.utc_now()]) do
      {1, _receipts} -> :ok
      {0, _receipts} -> {:error, :gone}
    end
  end

  defp insert_transaction(scope, attrs) do
    {units, attrs} = Map.pop!(attrs, :units)

    Repo.insert!(
      struct!(Transaction, attrs)
      |> Map.merge(%{
        user_id: scope.user.id,
        units: Enum.map(units, &struct!(TransactionUnit, &1))
      })
    )
  end

  @doc "The params that show a transaction the user booked in the transaction form."
  def transaction_form_params(%Transaction{} = transaction),
    do: TransactionForm.params_of(transaction)

  @doc """
  Saves the transaction form with `attrs` over `transaction`, one the user booked: its fields and
  units. A new PDF `receipt` replaces the attached one, which goes once nothing uses it.
  """
  def update_transaction(
        %Scope{} = scope,
        choices,
        %Transaction{} = transaction,
        attrs,
        receipt \\ nil
      ) do
    changeset = change_transaction_form(scope, choices, attrs, transaction)

    with :ok <- check_editable(scope, transaction),
         {:ok, {updated, unused}} <-
           transact_with_receipt(receipt, fn ->
             save_transaction(scope, changeset, transaction, receipt)
           end) do
      remove_receipt_file(unused)
      {:ok, updated}
    end
  end

  defp save_transaction(scope, changeset, transaction, receipt) do
    with {:ok, form} <- Ecto.Changeset.apply_action(changeset, :update),
         %Transaction{} <- Repo.get(Transaction, transaction.id) || {:error, :gone},
         [attrs] = TransactionForm.to_transactions(%{form | remove_at_once: false}),
         attrs = %{attrs | date_time: keep_time_of_day(attrs.date_time, transaction.date_time)},
         {units, attrs} = Map.pop!(attrs, :units),
         true <-
           keeps_holding?(scope, transaction, struct!(Transaction, attrs)) ||
             {:error, holding_error(changeset, form.kind)},
         {:ok, receipt_id} <- store_receipt(scope, receipt, changeset) do
      attrs =
        attrs |> Map.delete(:source) |> Map.put(:receipt_id, receipt_id || transaction.receipt_id)

      Repo.delete_all(from u in TransactionUnit, where: u.transaction_id == ^transaction.id)
      Repo.update!(Ecto.Changeset.change(transaction, attrs))

      Repo.insert_all(
        TransactionUnit,
        Enum.map(units, &Map.put(&1, :transaction_id, transaction.id))
      )

      unused = if receipt_id, do: drop_unused_receipt(transaction.receipt_id)

      with :ok <- CashSide.sync(scope),
           do: {:ok, {get_transaction(scope, transaction.id), unused}}
    end
  end

  # The time of day orders a day's transactions, so an edit keeps it.
  defp keep_time_of_day(date_time, stored),
    do: NaiveDateTime.new!(NaiveDateTime.to_date(date_time), NaiveDateTime.to_time(stored))

  defp holding_error(changeset, kind) do
    field = if kind in [:purchase, :sale], do: :shares, else: :date

    Ecto.Changeset.add_error(
      %{changeset | action: :update},
      field,
      "würde den Bestand später unter null bringen"
    )
  end

  @doc """
  Deletes a transaction of the user, of any type, and its receipt and the receipt's file once
  nothing uses them; refused with `{:error, :holding}` when a portfolio would later hold fewer
  shares than none without it.
  """
  def delete_transaction(%Scope{} = scope, %Transaction{} = transaction) do
    with :ok <- check_own(scope, transaction),
         true <- keeps_holding?(scope, transaction, nil) || {:error, :holding},
         {:ok, unused} <- Sync.write(fn -> remove_transaction(scope, transaction) end) do
      remove_receipt_file(unused)
      {:ok, transaction}
    end
  end

  defp remove_transaction(scope, transaction) do
    with :ok <- CashSide.release(scope, transaction) do
      Repo.delete!(transaction, allow_stale: true)
      {:ok, drop_unused_receipt(transaction.receipt_id)}
    end
  end

  defp check_editable(scope, transaction) do
    with :ok <- check_own(scope, transaction) do
      if Transaction.editable?(transaction), do: :ok, else: {:error, :read_only}
    end
  end

  defp check_own(%Scope{user: %{id: user_id}}, %Transaction{user_id: user_id}), do: :ok
  defp check_own(_scope, _transaction), do: {:error, :read_only}

  # Returns the file's hash once no user's receipt needs the file any more.
  defp drop_unused_receipt(nil), do: nil

  defp drop_unused_receipt(id) do
    with false <- Repo.exists?(from t in Transaction, where: t.receipt_id == ^id),
         %Receipt{sha256: sha256} = receipt <- Repo.get(Receipt, id) do
      Repo.delete!(receipt)
      unless Repo.exists?(from r in Receipt, where: r.sha256 == ^sha256), do: sha256
    else
      _used -> nil
    end
  end

  defp remove_receipt_file(nil), do: :ok

  defp remove_receipt_file(sha256) do
    _gone_already_is_fine = File.rm(receipt_file(sha256))
    :ok
  end

  # A receipt's file is written before its record commits; it goes again if none is committed.
  defp transact_with_receipt(receipt, fun) do
    Sync.write(fun)
  after
    remove_orphan_receipt_file(receipt)
  end

  defp remove_orphan_receipt_file(nil), do: :ok

  defp remove_orphan_receipt_file({path, _filename}) do
    sha256 = path |> File.read!() |> sha256()

    if Repo.exists?(from r in Receipt, where: r.sha256 == ^sha256),
      do: :ok,
      else: remove_receipt_file(sha256)
  end

  defp store_receipt(_scope, nil, _changeset), do: {:ok, nil}

  defp store_receipt(scope, {path, filename}, changeset) do
    content = File.read!(path)

    case store_receipt_file(content) do
      {:ok, sha256} ->
        {:ok, receipt_record(scope, sha256, filename, byte_size(content)).id}

      {:error, :not_pdf} ->
        {:error,
         Ecto.Changeset.add_error(%{changeset | action: :insert}, :receipt, "ist keine PDF-Datei")}
    end
  end

  @doc """
  Stores the PDF `content` in the receipts directory, once for all users, and returns its
  SHA-256; `{:error, :not_pdf}` for content that is no PDF.
  """
  def store_receipt_file(content) do
    if pdf?(content) do
      sha256 = sha256(content)
      file = receipt_file(sha256)
      File.mkdir_p!(Path.dirname(file))
      unless File.exists?(file), do: write_atomically(file, content)
      {:ok, sha256}
    else
      {:error, :not_pdf}
    end
  end

  defp pdf?(content), do: String.starts_with?(content, "%PDF-")

  defp sha256(content), do: :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)

  defp write_atomically(file, content) do
    temp = "#{file}.#{System.unique_integer([:positive])}.tmp"

    try do
      File.write!(temp, content)
      File.rename!(temp, file)
    after
      File.rm(temp)
    end
  end

  # The same file waiting in the inbox, or discarded from it, is booked with the transaction.
  defp receipt_record(scope, sha256, filename, byte_size) do
    case Repo.get_by(Receipt, user_id: scope.user.id, sha256: sha256) do
      nil ->
        Repo.insert!(%Receipt{
          user_id: scope.user.id,
          sha256: sha256,
          filename: filename,
          byte_size: byte_size
        })

      %Receipt{status: :booked} = receipt ->
        receipt

      receipt ->
        Repo.update!(Ecto.Changeset.change(receipt, status: :booked))
    end
  end

  @doc "Where the file of a receipt lies: in `receipts/` next to the database, named by its hash."
  def receipt_file(%Receipt{sha256: sha256}), do: receipt_file(sha256)

  def receipt_file(sha256) when is_binary(sha256) do
    Repo.config()
    |> Keyword.fetch!(:database)
    |> Path.dirname()
    |> Path.join("receipts/#{sha256}.pdf")
  end
end
