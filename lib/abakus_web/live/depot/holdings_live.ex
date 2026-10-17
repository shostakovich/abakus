defmodule AbakusWeb.Depot.HoldingsLive do
  use AbakusWeb, :depot_live_view

  import AbakusWeb.Depot.AllocationComponents

  alias Abakus.Depot.{MarketData, Portfolios}
  alias Abakus.Depot.Portfolios.Account
  alias Abakus.{Format, LocalTime, Money}
  alias AbakusWeb.Depot.Format, as: DepotFormat

  # Allocation tab, also its URL parameter, and label; the first is the default. A taxonomy's tab
  # is its id.
  @allocation_tabs [regions: "Regionen", sectors: "Sektoren"]
  @allocation_params Map.new(@allocation_tabs, fn {tab, _label} -> {Atom.to_string(tab), tab} end)
  @default_tab @allocation_tabs |> hd() |> elem(0)

  @source "Durchsicht durch die Fonds mit den Länder- und Sektordaten von DivvyDiary"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={{:depots, shown_portfolio_id(assigns)}}
    >
      <.depots_header
        tab={:holdings}
        portfolio={@holdings.portfolio}
        portfolios={@holdings.portfolios}
        switch_path={&holdings_path(portfolio: &1, allocation: @allocation_tab)}
      >
        <:subtitle>{subtitle(@holdings)}</:subtitle>
      </.depots_header>

      <.table
        id="holdings"
        groups={groups(@holdings)}
        row_id={& &1.id}
        row_link={&row_link/1}
      >
        <:col :let={item} label="Wertpapier" class="min-w-52">
          <.position_name item={item} />
        </:col>
        <:col :let={item} label="Stück" align={:end} show_from={:xl}>
          <span :if={item.type == :holding}>{DepotFormat.shares(item.entry.shares)}</span>
        </:col>
        <:col :let={item} label="Kurs" align={:end} show_from={:xl}>
          <span :if={item.type == :holding}>{price(item.entry)}</span>
        </:col>
        <:col :let={item} label="Wert" align={:end}>
          <.amount :if={item.type != :none} value={item.entry.value} class="font-semibold" />
          <.cell_sub :if={item.type == :holding} hide_from={:sm}>
            <.gain gain={item.entry.gain} purchase_value={item.entry.purchase_value} />
          </.cell_sub>
        </:col>
        <:col :let={item} label="Einstand" align={:end} show_from={:md}>
          <.amount :if={item.type == :holding} value={item.entry.purchase_value} />
        </:col>
        <:col :let={item} label="Gewinn" align={:end} show_from={:sm}>
          <.gain
            :if={item.type == :holding}
            gain={item.entry.gain}
            purchase_value={item.entry.purchase_value}
          />
        </:col>
        <:col :let={item} label="Anteil" align={:end} show_from={:lg}>
          <span :if={item.type != :none}>{share(item.entry.value, @holdings.net_worth)}</span>
        </:col>
        <:col :let={item} :if={@yields?} label="Div.-Rendite" align={:end} show_from={:"2xl"}>
          <span :if={item.type == :holding} class={muted(item.entry.dividends)}>
            {dividend_yield(item.entry.dividends, item.entry.value)}
          </span>
        </:col>
        <:foot>
          <th scope="row" id="holdings-total">
            {if @holdings.portfolio,
              do: DepotFormat.portfolio_name(@holdings.portfolio),
              else: "Gesamt"}
          </th>
          <td class={show_from(:xl)}></td>
          <td class={show_from(:xl)}></td>
          <td class="text-end whitespace-nowrap">
            <.amount value={@holdings.total.value} />
            <.cell_sub hide_from={:sm}><.gain gain={@holdings.total.gain} /></.cell_sub>
          </td>
          <td class={["text-end whitespace-nowrap", show_from(:md)]}>
            <.amount value={@holdings.total.purchase_value} />
          </td>
          <td class={["text-end whitespace-nowrap", show_from(:sm)]}>
            <.gain gain={@holdings.total.gain} />
          </td>
          <td class={["text-end whitespace-nowrap", show_from(:lg)]}>
            {@holdings.portfolio && share(@holdings.total.value, @holdings.net_worth)}
          </td>
          <td :if={@yields?} class={["text-end whitespace-nowrap", show_from(:"2xl")]}>
            {dividend_yield(@holdings.total.dividends, @holdings.total.securities_value)}
          </td>
        </:foot>
      </.table>
      <p :if={@yields?} class="mt-2 hidden text-sm text-base-content/70 2xl:block">
        Div.-Rendite: brutto, nächste 12 Monate auf den heutigen Wert.
      </p>

      <div
        :if={@holdings.costs.funds != []}
        class="mt-8 grid gap-x-10 gap-y-8 2xl:grid-cols-2"
      >
        <.allocation
          allocation={@holdings.allocation}
          tab={shown_tab(assigns)}
          tabs={allocation_tabs(assigns)}
          available={@compositions_available}
        />
        <.costs costs={@holdings.costs} />
      </div>
    </Layouts.depot>
    """
  end

  attr :item, :map, required: true, doc: "an item of `groups/2`"

  # A security with its ISIN or, below xl, its shares and price; an account with what it is in its
  # portfolio; the note of a portfolio without securities.
  defp position_name(%{item: %{type: :holding, entry: entry}} = assigns) do
    assigns = assign(assigns, :entry, entry)

    ~H"""
    {@entry.security.name}
    <.cell_sub :if={@entry.security.isin} show_from={:xl}>{@entry.security.isin}</.cell_sub>
    <.cell_sub hide_from={:xl} class="tabular-nums">
      <span class="whitespace-nowrap">{DepotFormat.shares(@entry.shares)} Stück</span><.meta_sep /><span class="whitespace-nowrap">{price(
        @entry
      )}</span>
    </.cell_sub>
    """
  end

  defp position_name(%{item: %{type: :account}} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-2 font-medium">
      <.icon name="wallet" class="text-base-content/70" />{@item.entry.account.name}
    </span>
    <.cell_sub :if={@item.note} class="whitespace-nowrap">{@item.note}</.cell_sub>
    """
  end

  defp position_name(%{item: %{type: :none}} = assigns) do
    ~H"""
    <span class="text-sm text-base-content/70">Keine Wertpapiere</span>
    """
  end

  defp row_link(%{type: :holding, entry: entry}), do: ~p"/depot/securities/#{entry.security}"
  defp row_link(_item), do: nil

  # A group per portfolio, its securities, a note when it has none, and its reference account;
  # last the accounts of no portfolio as „Konten“.
  defp groups(holdings), do: Enum.map(holdings.groups, &group/1)

  defp group(%{portfolio: nil} = group),
    do: %{id: "accounts", label: "Konten", rows: accounts(group)}

  defp group(%{portfolio: portfolio} = group) do
    securities =
      for entry <- group.holdings,
          do: %{type: :holding, id: "holding-#{portfolio.id}-#{entry.security.id}", entry: entry}

    none =
      if group.holdings == [],
        do: [%{type: :none, id: "holdings-none-#{portfolio.id}"}],
        else: []

    %{
      id: "portfolio-#{portfolio.id}",
      label: DepotFormat.portfolio_name(portfolio),
      rows: securities ++ none ++ accounts(group)
    }
  end

  defp accounts(group) do
    for entry <- group.accounts do
      %{
        type: :account,
        id: "account-#{entry.account.id}",
        entry: entry,
        note: account_note(group, entry.account)
      }
    end
  end

  attr :allocation, :map, required: true
  attr :tab, :any, required: true, doc: "`:regions`, `:sectors` or the id of a taxonomy"
  attr :tabs, :list, required: true, doc: "each with its `label`, `path` and whether `active`"
  attr :available, :boolean, required: true, doc: "whether DivvyDiary has its API key"

  defp allocation(assigns) do
    ~H"""
    <section id="allocation" aria-labelledby="allocation-title">
      <.section_heading id="allocation-title">Aufteilung</.section_heading>
      <.tabs label="Aufteilung nach" class="mb-4">
        <:tab :for={tab <- @tabs} patch={tab.path} active={tab.active}>{tab.label}</:tab>
      </.tabs>
      <.composition :if={is_atom(@tab)} allocation={@allocation} tab={@tab} available={@available} />
      <.classifications
        :if={is_integer(@tab)}
        allocation={taxonomy_allocation(@allocation, @tab)}
      />
    </section>
    """
  end

  attr :allocation, :map, required: true
  attr :tab, :atom, required: true
  attr :available, :boolean, required: true

  # Regions or sectors from the compositions of the funds.
  defp composition(assigns) do
    assigns = assign(assigns, :rows, Map.fetch!(assigns.allocation, assigns.tab))

    ~H"""
    <.missing_key :if={!@available} />
    <.composition_bars :if={@available} id="allocation-rows" rows={@rows} />
    <p :if={@available} class="mt-4 max-w-prose text-sm text-base-content/70">
      {source(@allocation.as_of)} Konten zählen nicht mit.
      <span :if={Enum.any?(@rows, &is_nil(&1.key))}>
        „Ohne Angabe“: Wertpapiere ohne Länder- oder Sektordaten von DivvyDiary.
      </span>
    </p>
    """
  end

  attr :allocation, :map, required: true, doc: "into a taxonomy, see `Classifications.of/3`"

  # The top-level classifications of a taxonomy against their targets.
  defp classifications(assigns) do
    rows = assigns.allocation.classifications

    assigns =
      assign(assigns, rows: rows, max: bar_max(Enum.flat_map(rows, &[&1.share, &1.target])))

    ~H"""
    <ul id="allocation-rows" class="flex flex-col gap-3">
      <li :for={entry <- @rows} id={"classification-#{entry.classification.id}"}>
        <.bar
          label={entry.classification.name}
          value={bar_value(entry.share)}
          max={@max}
          target={bar_value(entry.target)}
          show_value
          value_label={in_percent(entry.share)}
        >
          Ziel {in_percent(entry.target)}
          <.badge :if={entry.deviation} tone={deviation_tone(entry.deviation)} class="ms-1">
            {deviation_label(entry.deviation)}
          </.badge>
        </.bar>
      </li>
    </ul>
    <p class="mt-4 max-w-prose text-sm text-base-content/70">
      <span :if={@allocation.unassigned}>
        Ohne Kategorie: {unassigned(@allocation.unassigned)}. Die Anteile beziehen sich wie die
        Ziele auf den zugeordneten Wert.
      </span>
      {join_meta(["Balken: Ist", "Strich: dein Ziel"])}
    </p>
    """
  end

  attr :costs, :map, required: true

  defp costs(assigns) do
    ~H"""
    <section id="costs" aria-labelledby="costs-title">
      <.section_heading id="costs-title">
        Kosten
        <:actions :if={@costs.ter}>
          <span class="text-sm text-base-content/70">gewichtet {DepotFormat.ter(@costs.ter)}</span>
        </:actions>
      </.section_heading>
      <.table id="cost-rows" rows={@costs.funds} row_id={&"cost-#{&1.security.id}"} size={:sm}>
        <:col :let={fund} label="Wertpapier">
          <.link navigate={~p"/depot/securities/#{fund.security}"} class="hover:underline">
            {fund.security.name}
          </.link>
          <.cell_sub :if={fund.fund_size} hide_from={:sm} class="tabular-nums whitespace-nowrap">
            Fondsgröße {fund_size(fund)}
          </.cell_sub>
        </:col>
        <:col :let={fund} label="TER" align={:end}>{DepotFormat.ter(fund.ter)}</:col>
        <:col :let={fund} label="Größe" align={:end} show_from={:sm}>{fund_size(fund)}</:col>
        <:col :let={fund} label="pro Jahr" align={:end}><.per_year cents={fund.per_year} /></:col>
        <:foot>
          <th scope="row">Gesamt</th>
          <td class="text-end">{DepotFormat.ter(@costs.ter)}</td>
          <td class={show_from(:sm)}></td>
          <td class="text-end whitespace-nowrap"><.per_year cents={@costs.per_year} /></td>
        </:foot>
      </.table>
      <p class="mt-2 max-w-prose text-sm text-base-content/70">
        Laufende Kosten, die im Kurs stecken. Ordergebühren kommen aus den Buchungen.
        <span :if={Enum.any?(@costs.funds, &is_nil(&1.ter))}>
          Wertpapiere ohne TER zählen nicht mit.
        </span>
      </p>
    </section>
    """
  end

  # The holdings with `params`; nil and the default tab are left out.
  defp holdings_path(params) do
    query =
      params
      |> Keyword.update(:allocation, nil, &allocation_param/1)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    ~p"/depot/holdings?#{query}"
  end

  defp allocation_param(@default_tab), do: nil
  defp allocation_param(tab) when is_atom(tab), do: Atom.to_string(tab)
  defp allocation_param(taxonomy_id), do: Integer.to_string(taxonomy_id)

  # Regions, sectors, then each taxonomy with value shown in it. A tab keeps the portfolio.
  defp allocation_tabs(assigns) do
    shown = shown_tab(assigns)

    taxonomies =
      for %{taxonomy: taxonomy} <- assigns.holdings.allocation.taxonomies,
          do: {taxonomy.id, taxonomy.name}

    for {tab, label} <- @allocation_tabs ++ taxonomies do
      path =
        holdings_path(portfolio: shown_portfolio_id(assigns), allocation: tab)

      %{label: label, path: path, active: tab == shown}
    end
  end

  # The tab in the URL; the first for a taxonomy without value shown in it.
  defp shown_tab(%{allocation_tab: id, holdings: holdings}) when is_integer(id) do
    if taxonomy_allocation(holdings.allocation, id), do: id, else: @default_tab
  end

  defp shown_tab(%{allocation_tab: tab}), do: tab

  defp taxonomy_allocation(allocation, id),
    do: Enum.find(allocation.taxonomies, &(&1.taxonomy.id == id))

  # The portfolio shown, nil for all, which the sidebar marks.
  defp shown_portfolio_id(%{holdings: %{portfolio: %{id: id}}}), do: id
  defp shown_portfolio_id(_assigns), do: nil

  defp subtitle(%{portfolio: nil, portfolios: portfolios, groups: groups}) do
    securities = groups |> Enum.flat_map(& &1.holdings) |> Enum.uniq_by(& &1.security.id)
    accounts = Enum.flat_map(groups, & &1.accounts)

    join_meta([
      count(length(portfolios), "Depot", "Depots"),
      count(length(securities), "Wertpapier", "Wertpapiere"),
      count(length(accounts), "Konto", "Konten")
    ])
  end

  defp subtitle(%{groups: [group]}) do
    join_meta([
      count(length(group.holdings), "Wertpapier", "Wertpapiere"),
      group.accounts != [] && "davon Cash\u00A0#{Money.euros(group.cash)}"
    ])
  end

  defp count(0, _one, many), do: "keine\u00A0#{many}"
  defp count(1, one, _many), do: "1\u00A0#{one}"
  defp count(count, _one, many), do: "#{count}\u00A0#{many}"

  defp account_note(%{portfolio: nil}, _account), do: nil

  defp account_note(_portfolio_group, account) do
    case Account.role(account) do
      {:portfolio_cash, _portfolio_id} -> "Cash"
      _none -> "Referenzkonto"
    end
  end

  defp price(%{price: price, security: security}), do: DepotFormat.price(price, security.currency)

  defp deviation_tone(:above), do: :warning
  defp deviation_tone(:below), do: :error

  defp deviation_label(:above), do: "über Ziel"
  defp deviation_label(:below), do: "unter Ziel"

  defp unassigned(%{value: value, share: nil}), do: Money.euros(value)

  defp unassigned(%{value: value, share: share}),
    do: "#{Money.euros(value)} (#{in_percent(share)} des Werts)"

  defp source(nil), do: @source <> "."

  defp source(as_of), do: "#{@source}, Stand #{Format.date(as_of)}."

  defp fund_size(fund), do: DepotFormat.fund_size(fund.fund_size, fund.security.currency)

  attr :cents, :integer, required: true, doc: "nil without a TER"

  defp per_year(assigns) do
    ~H"""
    <span :if={!@cents}>–</span><.amount :if={@cents} value={@cents} decimals={0} />
    """
  end

  defp dividend_yield(cents, value) when cents <= 0 or value <= 0, do: "–"
  defp dividend_yield(cents, value), do: cents |> Format.percent_of(value) |> Format.percent()

  defp share(_value, net_worth) when net_worth <= 0, do: nil
  defp share(value, net_worth), do: value |> Format.percent_of(net_worth) |> Format.percent()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Bestand",
       compositions_available: MarketData.divvy_diary_available?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign(portfolio_id: parse_id(params["portfolio"]))
    |> assign(allocation_tab: allocation_tab(params["allocation"]))
    |> load_holdings()
    |> then(&{:noreply, &1})
  end

  # Regions, sectors or the id of a taxonomy.
  defp allocation_tab(param),
    do: Map.get(@allocation_params, param) || parse_id(param) || @default_tab

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_holdings(socket)}

  defp load_holdings(socket) do
    %{current_scope: scope, portfolio_id: portfolio_id} = socket.assigns
    holdings = Portfolios.holdings(scope, portfolio_id, LocalTime.today())
    assign(socket, holdings: holdings, yields?: yields?(holdings))
  end

  # The dividend yield column only when a position has one.
  defp yields?(holdings) do
    holdings.groups
    |> Enum.flat_map(& &1.holdings)
    |> Enum.any?(&(&1.dividends > 0 and &1.value > 0))
  end
end
