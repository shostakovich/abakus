defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  alias Abakus.Names
  alias AbakusWeb.{AccountGroups, AccountMotif, Areas}
  alias AbakusWeb.Depot.{Components, Format, TransactionDialog}

  @budget_pages [:budget, :accounts, :all_accounts, :import]
  @kasse_pages [:kasse_expenses, :kasse_balances, :kasse_activity]
  @depot_pages [:depot_wealth, :depots, :import_receipts]

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :current, :atom,
    default: nil,
    values:
      [nil, :budget, :accounts, :all_accounts, :import] ++
        @kasse_pages ++ @depot_pages,
    doc: "the page shown; Import & Sync's tabs are `:import` and `:import_receipts`"

  attr :areas, :list, required: true, doc: "the areas the user may use, from `AbakusWeb.Areas`"

  attr :area, :atom,
    required: true,
    doc: "the current area's key; the sidebar and the dock show its entries"

  attr :account_groups, :list,
    default: [],
    doc: "from `AbakusWeb.AccountGroups`; Finanzen lists the open ones"

  attr :account_id, :integer, default: nil, doc: "the account whose register is shown"

  attr :depot_sidebar, :map,
    default: nil,
    doc: "the portfolios with their values from `AbakusWeb.Depot.Sidebar`, which Finanzen lists"

  attr :depot_marked, :any,
    default: nil,
    doc: "on the Depots pages: the portfolio they show, `{:depot_portfolio, id}`"

  attr :account_dialog, :map,
    default: nil,
    doc: "the open account form from `AbakusWeb.AccountDialog`, if any"

  attr :width, :atom,
    default: :default,
    values: [:narrow, :default, :wide, :full],
    doc: "the page's width in the shell"

  slot :inner_block, required: true
  slot :fab, doc: "the page's main action on phones, a `<.fab>`"

  @doc """
  Signed-in pages in Setzkasten's sidebar shell, showing the current area's entries, then the settings.

  Finanzen: Budget, Vermögen, Alle Konten, Alle Depots and Import & Sync with the receipts waiting in the inbox, the
  open budget and tracking accounts but the portfolios' cash with their emoji (else `AbakusWeb.AccountMotif`), their
  balance and how many transactions wait for approval; then the section Depots with the active portfolios and their
  values, each shown with the leading emoji of its name, else the briefcase; a user without the budget sees only
  Vermögen, Alle Depots, Import & Sync and Depots. The Kasse: Ausgaben, Salden and Aktivität. Accounts and portfolios
  stay out of the icon rail and the dock. Entries show plush images, the Lucide icon only where a plush has no image.

  With one area the brand is its name; with more, a segmented switch tops the sidebar, and in the top bar the
  brand is a menu that switches the area. On phones the dock holds the current area's pages; its "Mehr" opens
  the sidebar with everything else, and the account menu offers the settings too.
  """
  def app(assigns) do
    finanzen? = assigns.area == :finanzen

    assigns =
      assign(assigns,
        finanzen?: finanzen?,
        budget?: finanzen? and Areas.allowed?(assigns.current_scope, :budget),
        depot?: finanzen? and Areas.allowed?(assigns.current_scope, :depot),
        kasse?: assigns.area == :kasse,
        groups: sidebar_groups(finanzen?, assigns),
        portfolios: portfolio_rows(finanzen?, assigns.depot_sidebar),
        import_path: import_path(assigns.current_scope),
        inbox: inbox(assigns.depot_sidebar),
        nav_key: nav_key(assigns)
      )

    assigns = assign(assigns, :depots_total, Enum.sum_by(assigns.portfolios, & &1.value))

    ~H"""
    <.app_shell
      layout={:sidebar}
      current={@nav_key}
      current_area={@area}
      area_label="Bereich wechseln"
      width={@width}
      amount_tone={:negative}
    >
      <:brand :let={place}>
        <img src={~p"/images/icon-192.webp"} alt="" width="28" height="28" class="size-7 shrink-0" />
        <.area_switcher :if={place == :bar and length(@areas) > 1} areas={@areas} area={@area} />
        <span :if={place != :bar or length(@areas) < 2} class="truncate">
          {brand_name(@areas)}
        </span>
      </:brand>
      <:area
        :for={area <- @areas}
        key={area.key}
        id={"area-#{area.key}"}
        label={area.label}
        plush={area.plush}
        icon={area.icon}
        href={area.path}
      />
      <:nav
        :if={@budget?}
        key={:budget}
        id="side-budget"
        label="Budget"
        plush="wallet"
        icon="wallet"
        navigate={navigate(~p"/budget", @current)}
        href={href(~p"/budget", @current)}
      />
      <:nav
        :if={@finanzen?}
        key={:depot_wealth}
        id="side-depot-wealth"
        label="Vermögen"
        plush="trending-up"
        icon="trending-up"
        navigate={navigate(~p"/depot", @current)}
        href={href(~p"/depot", @current)}
      />
      <:nav
        :if={@budget?}
        key={:all_accounts}
        id="side-all-accounts"
        label="Alle Konten"
        plush="landmark"
        icon="landmark"
        navigate={navigate(~p"/budget/accounts/all", @current)}
        href={href(~p"/budget/accounts/all", @current)}
      />
      <:nav
        :if={@depot?}
        key={:depots}
        id="side-depots"
        label="Alle Depots"
        plush="briefcase"
        icon="chart-pie"
        navigate={navigate(~p"/depot/holdings", @current)}
        href={href(~p"/depot/holdings", @current)}
      />
      <:nav
        :if={@finanzen?}
        key={:import}
        id="side-import"
        label="Import & Sync"
        plush="inbox"
        icon="refresh-cw"
        dock={false}
        count={if @inbox > 0, do: @inbox}
        count_label="im Eingang"
        navigate={navigate(@import_path, @current)}
        href={href(@import_path, @current)}
      />
      <:nav
        :for={{group, row, first?} <- account_rows(@groups)}
        key={{:account, row.account.id}}
        id={"side-account-#{row.account.id}"}
        label={label(row.account.name)}
        glyph={glyph(row.account.name)}
        plush={if !glyph(row.account.name), do: AccountMotif.for_account(row.account)}
        amount={row.balance}
        count={if row.unapproved > 0, do: row.unapproved}
        count_label="zu bestätigen"
        section={account_section(group)}
        section_amount={if first?, do: group.balance}
        rail={false}
        dock={false}
        parent={:all_accounts}
        navigate={navigate(~p"/budget/accounts/#{row.account}", @current)}
        href={href(~p"/budget/accounts/#{row.account}", @current)}
      />
      <:nav
        :for={{row, first?} <- Enum.with_index(@portfolios, &{&1, &2 == 0})}
        key={{:depot_portfolio, row.portfolio.id}}
        id={"side-depot-portfolio-#{row.portfolio.id}"}
        label={row.label}
        glyph={row.glyph}
        plush={if !row.glyph, do: "briefcase"}
        icon={if !row.glyph, do: "chart-pie"}
        amount={row.value}
        section="Depots"
        section_amount={if first?, do: @depots_total}
        rail={false}
        dock={false}
        parent={:depots}
        navigate={navigate(Components.depots_path(:holdings, row.portfolio.id), @current)}
        href={href(Components.depots_path(:holdings, row.portfolio.id), @current)}
      />
      <:nav
        :if={@kasse?}
        key={:kasse_expenses}
        id="side-kasse-expenses"
        label="Ausgaben"
        plush="receipt"
        icon="receipt"
        navigate={navigate(~p"/kasse", @current)}
        href={href(~p"/kasse", @current)}
      />
      <:nav
        :if={@kasse?}
        key={:kasse_balances}
        id="side-kasse-balances"
        label="Salden"
        plush="scale"
        icon="scale"
        navigate={navigate(~p"/kasse/balances", @current)}
        href={href(~p"/kasse/balances", @current)}
      />
      <:nav
        :if={@kasse?}
        key={:kasse_activity}
        id="side-kasse-activity"
        label="Aktivität"
        plush="activity"
        icon="activity"
        navigate={navigate(~p"/kasse/activity", @current)}
        href={href(~p"/kasse/activity", @current)}
      />
      <:nav
        key={:settings}
        id="side-settings"
        label="Einstellungen"
        plush="settings"
        icon="settings"
        dock={false}
        href={~p"/settings"}
      />
      <:account :let={place}>
        <.user_menu place={place} email={@current_scope.user.email} />
      </:account>
      <:fab :if={@fab != []}>{render_slot(@fab)}</:fab>
      {render_slot(@inner_block)}
    </.app_shell>

    <.flash_group flash={@flash} />
    <.confirm_dialog />
    <.live_component
      :if={@account_dialog}
      module={AbakusWeb.AccountDialog}
      id="account-dialog"
      current_scope={@current_scope}
      account={@account_dialog.account}
      balance={@account_dialog.balance}
    />
    """
  end

  attr :place, :atom, required: true
  attr :email, :string, required: true

  defp user_menu(assigns) do
    ~H"""
    <.dropdown
      id={"user-menu-#{@place}"}
      label={@email}
      align={if @place == :bar, do: :end, else: :start}
      position={if @place == :sidebar, do: :top, else: :bottom}
      variant={:ghost}
      chevron={false}
      class={@place == :sidebar && "w-full"}
      trigger_class={if @place == :sidebar, do: "w-full justify-start", else: "btn-square"}
    >
      <:trigger>
        <.avatar initials={initial(@email)} size={:sm} shape={:round} tone={:primary} />
        <span :if={@place == :sidebar} class="truncate">{@email}</span>
      </:trigger>
      <:header :if={@place != :sidebar}>{@email}</:header>
      <:item href={~p"/settings"} icon="settings">
        Einstellungen
      </:item>
      <:item href={~p"/users/log-out"} method="delete" icon="log-out">Abmelden</:item>
    </.dropdown>
    """
  end

  defp import_path(scope),
    do: if(Areas.allowed?(scope, :budget), do: ~p"/budget/import", else: ~p"/depot/receipts")

  defp inbox(%{inbox: inbox}), do: inbox
  defp inbox(_sidebar), do: 0

  defp account_rows(groups) do
    for group <- groups, {row, index} <- Enum.with_index(group.rows), do: {group, row, index == 0}
  end

  defp sidebar_groups(true = _finanzen?, assigns), do: AccountGroups.open(assigns.account_groups)
  defp sidebar_groups(_finanzen?, _assigns), do: []

  defp portfolio_rows(true, %{portfolios: rows}) do
    for row <- rows do
      name = Format.portfolio_name(row.portfolio)
      Map.merge(row, %{label: label(name), glyph: glyph(name)})
    end
  end

  defp portfolio_rows(_finanzen?, _sidebar), do: []

  defp glyph(name), do: name |> Names.split_emoji() |> elem(0)

  defp label(name), do: name |> Names.split_emoji() |> elem(1)

  defp nav_key(%{current: :accounts, account_id: account_id} = assigns) do
    listed? =
      Enum.any?(
        AccountGroups.rows(sidebar_groups(true, assigns)),
        &(&1.account.id == account_id)
      )

    if account_id && listed?, do: {:account, account_id}, else: :all_accounts
  end

  defp nav_key(%{current: :depots, depot_marked: marked, depot_sidebar: sidebar})
       when marked != nil and sidebar != nil do
    listed = Enum.map(sidebar.portfolios, &{:depot_portfolio, &1.portfolio.id})
    if marked in listed, do: marked, else: :depots
  end

  defp nav_key(%{current: :import_receipts}), do: :import
  defp nav_key(%{current: current}), do: current

  defp initial(email), do: String.upcase(String.first(email) || "")

  # The areas and settings have live_sessions of their own; only links within one navigate.
  defp navigate(path, current) do
    if same_live_session?(path, current), do: path
  end

  defp href(path, current) do
    if !same_live_session?(path, current), do: path
  end

  defp same_live_session?("/budget" <> _, current), do: current in @budget_pages
  defp same_live_session?("/kasse" <> _, current), do: current in @kasse_pages
  defp same_live_session?("/depot" <> _, current), do: current in @depot_pages

  defp account_section(%{key: :budget}), do: "Budgetkonten"
  defp account_section(%{key: :tracking}), do: "Trackingkonten"

  defp brand_name([area]), do: area.label
  defp brand_name(_areas), do: "Abakus"

  attr :areas, :list, required: true
  attr :area, :atom, required: true

  defp area_switcher(assigns) do
    assigns = assign(assigns, :current, Enum.find(assigns.areas, &(&1.key == assigns.area)))

    ~H"""
    <.dropdown
      id="area-switcher"
      label="Bereich wechseln"
      variant={:ghost}
      class="min-w-0"
      trigger_class="min-w-0 px-2 text-base font-semibold"
    >
      <:trigger>
        <span class="truncate">{if @current, do: @current.label, else: "Abakus"}</span>
      </:trigger>
      <:item
        :for={area <- @areas}
        href={area.path}
        plush={area.plush}
        icon={area.icon}
        active={area.key == @area}
      >
        {area.label}
      </:item>
    </.dropdown>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :areas, :list, required: true
  attr :area, :atom, required: true
  attr :current, :atom, required: true, values: [:expenses, :balances, :activity]
  attr :fab, :boolean, default: true, doc: "false on forms, whose action bar is the main action"
  slot :inner_block, required: true

  @doc "The Kasse's pages: narrow, with „Ausgabe hinzufügen“ as the phone's floating button (not on forms)."
  def kasse(assigns) do
    ~H"""
    <.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:"kasse_#{@current}"}
      width={:narrow}
    >
      <:fab :if={@fab}>
        <.fab navigate={~p"/kasse/expenses/new"} label="Ausgabe hinzufügen" />
      </:fab>
      {render_slot(@inner_block)}
    </.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :areas, :list, required: true
  attr :area, :atom, required: true
  attr :account_groups, :list, required: true
  attr :account_dialog, :map, required: true

  attr :sidebar, :map,
    required: true,
    doc: "the portfolios, see `AbakusWeb.Depot.Sidebar`"

  attr :current, :any,
    required: true,
    doc: """
    what is open: `:wealth`, `:receipts` (Import & Sync's Belege), or a Depots page as
    `{:depots, portfolio_id}` with nil for all portfolios
    """

  slot :inner_block, required: true

  @doc """
  The Depot's pages: wide, with the dialog „Buchung erfassen“, which the Depots pages open from
  their header and on phones from the floating button.
  """
  def depot(assigns) do
    {page, marked} = depot_page(assigns.current)
    assigns = assign(assigns, page: page, marked: marked)

    ~H"""
    <.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={@page}
      depot_sidebar={@sidebar}
      depot_marked={@marked}
      width={:wide}
    >
      <:fab :if={@page == :depots}>
        <.fab id="fab-book" label="Buchung" phx-click={TransactionDialog.open()} />
      </:fab>
      {render_slot(@inner_block)}
    </.app>
    <.live_component
      module={TransactionDialog}
      id={TransactionDialog.id()}
      current_scope={@current_scope}
    />
    """
  end

  defp depot_page(:wealth), do: {:depot_wealth, nil}
  defp depot_page(:receipts), do: {:import_receipts, nil}

  defp depot_page({:depots, nil}), do: {:depots, nil}
  defp depot_page({:depots, portfolio_id}), do: {:depots, {:depot_portfolio, portfolio_id}}

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :areas, :list, required: true
  attr :area, :atom, required: true, doc: "the area used last, which the way back leads to"
  attr :groups, :list, required: true, doc: "from `AbakusWeb.SettingsNav`"
  attr :current, :atom, required: true, doc: "the section shown"
  slot :inner_block, required: true

  @doc """
  The settings: the sidebar in its settings mode, with the way back to the area used last and the sections grouped
  by area.
  """
  def settings(assigns) do
    current_session =
      Enum.find_value(assigns.groups, fn {_label, entries} ->
        Enum.find_value(entries, &(&1.key == assigns.current && &1.live_session))
      end)

    assigns =
      assign(assigns,
        back: Enum.find(assigns.areas, &(&1.key == assigns.area)),
        entries: nav_entries(assigns.groups, current_session)
      )

    ~H"""
    <.app_shell layout={:sidebar} current={@current} width={:narrow}>
      <:brand>
        <img src={~p"/images/icon-192.webp"} alt="" width="28" height="28" class="size-7 shrink-0" />
        <span class="truncate">{brand_name(@areas)}</span>
      </:brand>
      <:back :if={@back} id="settings-back" label={back_label(@back)} href={@back.path} />
      <:nav
        :for={{section, entry, navigate?} <- @entries}
        key={entry.key}
        id={"settings-#{entry.key |> Atom.to_string() |> String.replace("_", "-")}"}
        label={entry.label}
        plush={entry.plush}
        icon={entry.icon}
        section={section}
        navigate={if navigate?, do: entry.path}
        href={if !navigate?, do: entry.path}
      />
      <:account :let={place}>
        <.user_menu place={place} email={@current_scope.user.email} />
      </:account>
      {render_slot(@inner_block)}
    </.app_shell>

    <.flash_group flash={@flash} />
    <.confirm_dialog />
    """
  end

  defp nav_entries(groups, current_session) do
    for {label, entries} <- groups,
        entry <- entries,
        do: {label, entry, entry.live_session == current_session}
  end

  defp back_label(%{key: :kasse}), do: "Zurück zur Kasse"
  defp back_label(area), do: "Zurück zu #{area.label}"

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main
      id="main"
      class="mx-auto flex min-h-dvh max-w-md flex-col px-4 py-12 before:grow-[35] after:grow-[65]"
    >
      <h1 class="mb-6 flex items-center justify-center gap-2 text-2xl font-semibold">
        <img src={~p"/images/icon-192.webp"} alt="" width="32" height="32" class="size-8" /> Abakus
      </h1>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end
end
