defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  alias Abakus.Names
  alias AbakusWeb.AccountGroups

  @budget_pages [:budget, :accounts, :all_accounts, :import]
  @kasse_pages [:kasse_expenses, :kasse_balances, :kasse_activity, :kasse_settings]

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :current, :atom,
    default: nil,
    values: [nil, :budget, :accounts, :all_accounts, :import, :settings] ++ @kasse_pages

  attr :areas, :list, required: true, doc: "the areas the user may use, from `AbakusWeb.Areas`"
  attr :area, :atom, required: true, doc: "the current area's key; its entries go into the dock"

  attr :account_groups, :list,
    default: [],
    doc: "from `AbakusWeb.AccountGroups`; the sidebar lists the open ones"

  attr :account_id, :integer, default: nil, doc: "the account whose register is shown"

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
  Signed-in pages in Setzkasten's sidebar shell, grouped into the areas the user may use, then the settings.

  The Budget: Budget and all accounts, the open accounts by group with their balance and how many transactions
  wait for approval and "Konto hinzufügen" (not in the icon rail or the dock), then Import & Sync. The Kasse:
  Ausgaben, Salden, Aktivität and Gruppe (its settings).

  With one area the brand is its name; with more, each area's entries start with its name as section title, and
  in the top bar the brand is a menu that switches the area. On phones the dock holds the current area's entries;
  its "Mehr" opens the sidebar with everything else, and the account menu offers the settings too.
  """
  def app(assigns) do
    assigns =
      assign(assigns,
        budget?: Enum.any?(assigns.areas, &(&1.key == :budget)),
        groups: AccountGroups.open(assigns.account_groups),
        nav_key: nav_key(assigns.current, assigns.account_id, assigns.account_groups),
        kasse?: Enum.any?(assigns.areas, &(&1.key == :kasse)),
        in_budget_dock?: assigns.area == :budget,
        in_kasse_dock?: assigns.area == :kasse
      )

    ~H"""
    <.app_shell layout={:sidebar} current={@nav_key} width={@width} amount_tone={:negative}>
      <:brand :let={place}>
        <img src={~p"/images/icon.svg"} alt="" width="28" height="28" class="size-7 shrink-0" />
        <.area_switcher :if={place == :bar and length(@areas) > 1} areas={@areas} area={@area} />
        <span :if={place != :bar or length(@areas) < 2} class="truncate">
          {brand_name(@areas)}
        </span>
      </:brand>
      <:nav
        :if={@budget?}
        key={:budget}
        id="side-budget"
        label="Budget"
        icon="wallet"
        section={section(@areas, "Budget")}
        dock={@in_budget_dock?}
        navigate={navigate(~p"/budget", @current)}
        href={href(~p"/budget", @current)}
      />
      <:nav
        :if={@budget?}
        key={:all_accounts}
        id="side-all-accounts"
        label="Alle Konten"
        icon="landmark"
        dock={@in_budget_dock?}
        navigate={navigate(~p"/budget/accounts/all", @current)}
        href={href(~p"/budget/accounts/all", @current)}
      />
      <:nav
        :for={{group, row, first?} <- account_rows(@groups)}
        key={{:account, row.account.id}}
        id={"side-account-#{row.account.id}"}
        label={label(row.account.name)}
        glyph={glyph(row.account.name)}
        amount={row.balance}
        count={if row.unapproved > 0, do: row.unapproved}
        count_label="zu bestätigen"
        section={account_section(@areas, group)}
        section_amount={if first?, do: group.balance}
        rail={false}
        dock={false}
        parent={:all_accounts}
        navigate={navigate(~p"/budget/accounts/#{row.account}", @current)}
        href={href(~p"/budget/accounts/#{row.account}", @current)}
      />
      <:nav
        :if={@budget?}
        key={:add_account}
        id="side-add-account"
        label="Konto hinzufügen"
        icon="plus"
        section={List.last(@groups)[:label]}
        on_click={JS.push("open_account_dialog")}
      />
      <:nav
        :if={@budget?}
        key={:import}
        id="side-import"
        label="Import & Sync"
        icon="refresh-cw"
        dock={@in_budget_dock?}
        navigate={navigate(~p"/budget/import", @current)}
        href={href(~p"/budget/import", @current)}
      />
      <:nav
        :if={@kasse?}
        key={:kasse_expenses}
        id="side-kasse-expenses"
        label="Ausgaben"
        plush="receipt"
        icon="receipt"
        section={section(@areas, "Kasse")}
        dock={@in_kasse_dock?}
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
        dock={@in_kasse_dock?}
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
        dock={@in_kasse_dock?}
        navigate={navigate(~p"/kasse/activity", @current)}
        href={href(~p"/kasse/activity", @current)}
      />
      <:nav
        :if={@kasse?}
        key={:kasse_settings}
        id="side-kasse-settings"
        label="Gruppe"
        plush="users"
        icon="users"
        dock={@in_kasse_dock?}
        navigate={navigate(~p"/kasse/settings", @current)}
        href={href(~p"/kasse/settings", @current)}
      />
      <:nav
        key={:settings}
        id="side-settings"
        label="Einstellungen"
        icon="settings"
        dock={false}
        href={~p"/settings"}
      />
      <:account :let={place}>
        <.dropdown
          id={"user-menu-#{place}"}
          label={@current_scope.user.email}
          align={if place == :bar, do: :end, else: :start}
          position={if place == :sidebar, do: :top, else: :bottom}
          variant={:ghost}
          chevron={false}
          class={place == :sidebar && "w-full"}
          trigger_class={if place == :sidebar, do: "w-full justify-start", else: "btn-square"}
        >
          <:trigger>
            <.avatar
              initials={initial(@current_scope.user.email)}
              size={:sm}
              shape={:round}
              tone={:primary}
            />
            <span :if={place == :sidebar} class="truncate">{@current_scope.user.email}</span>
          </:trigger>
          <:header :if={place != :sidebar}>{@current_scope.user.email}</:header>
          <:item href={~p"/settings"} icon="settings">
            Einstellungen
          </:item>
          <:item href={~p"/users/log-out"} method="delete" icon="log-out">Abmelden</:item>
        </.dropdown>
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
      account={@account_dialog.account}
      balance={@account_dialog.balance}
    />
    """
  end

  defp account_rows(groups) do
    for group <- groups, {row, index} <- Enum.with_index(group.rows), do: {group, row, index == 0}
  end

  defp glyph(name), do: name |> Names.split_emoji() |> elem(0)

  defp label(name), do: name |> Names.split_emoji() |> elem(1)

  # The account shown, if the sidebar lists it; the account list and closed accounts belong to Alle Konten.
  defp nav_key(:accounts, account_id, groups) do
    listed? =
      Enum.any?(AccountGroups.rows(AccountGroups.open(groups)), &(&1.account.id == account_id))

    if account_id && listed?, do: {:account, account_id}, else: :all_accounts
  end

  defp nav_key(current, _account_id, _groups), do: current

  defp initial(email), do: String.upcase(String.first(email) || "")

  # Each area and the settings have live_sessions of their own (Zugang a further one behind the sudo plug), so
  # only links within an area navigate; the others load the page.
  defp navigate(path, current) do
    if same_area?(path, current), do: path
  end

  defp href(path, current) do
    if !same_area?(path, current), do: path
  end

  defp same_area?("/budget" <> _, current), do: current in @budget_pages
  defp same_area?("/kasse" <> _, current), do: current in @kasse_pages

  # With more than one area, "Budget" heads the area, so its account groups say what they hold.
  defp account_section([_one], group), do: group.label
  defp account_section(_areas, %{key: :budget}), do: "Budgetkonten"
  defp account_section(_areas, %{key: :tracking}), do: "Trackingkonten"

  defp brand_name([area]), do: area.label
  defp brand_name(_areas), do: "Abakus"

  # With more than one area, each area's first entry carries its name.
  defp section([_one], _label), do: nil
  defp section(_areas, label), do: label

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
  attr :account_groups, :list, required: true
  attr :account_dialog, :map, required: true
  attr :current, :atom, required: true, values: [:expenses, :balances, :activity, :settings]
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
      account_groups={@account_groups}
      account_dialog={@account_dialog}
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
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main
      id="main"
      class="mx-auto flex min-h-dvh max-w-md flex-col px-4 py-12 before:grow-[35] after:grow-[65]"
    >
      <h1 class="mb-6 flex items-center justify-center gap-2 text-2xl font-semibold">
        <img src={~p"/images/icon.svg"} alt="" width="32" height="32" class="size-8" /> Abakus
      </h1>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end
end
