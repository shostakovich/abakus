defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  alias Abakus.Names
  alias AbakusWeb.AccountGroups

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true

  attr :current, :atom,
    default: nil,
    values: [nil, :budget, :accounts, :all_accounts, :import, :settings]

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
  Signed-in pages in Setzkasten's sidebar shell: Budget and all accounts, the open accounts by group with their
  balance and how many transactions wait for approval and "Konto hinzufügen" (not in the icon rail or the dock),
  then Import & Sync and the settings. On phones the dock's "Mehr" opens the sidebar with the accounts and the
  settings, which the account menu also offers.
  """
  def app(assigns) do
    assigns =
      assign(assigns,
        groups: AccountGroups.open(assigns.account_groups),
        nav_key: nav_key(assigns.current, assigns.account_id, assigns.account_groups)
      )

    ~H"""
    <.app_shell layout={:sidebar} current={@nav_key} width={@width} amount_tone={:negative}>
      <:brand>
        <img src={~p"/images/icon.svg"} alt="" width="28" height="28" class="size-7 shrink-0" />
        Abakus
      </:brand>
      <:nav
        key={:budget}
        id="side-budget"
        label="Budget"
        icon="wallet"
        navigate={navigate(~p"/", @current)}
        href={href(~p"/", @current)}
      />
      <:nav
        key={:all_accounts}
        id="side-all-accounts"
        label="Alle Konten"
        icon="landmark"
        navigate={navigate(~p"/accounts/all", @current)}
        href={href(~p"/accounts/all", @current)}
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
        section={group.label}
        section_amount={if first?, do: group.balance}
        rail={false}
        dock={false}
        parent={:all_accounts}
        navigate={navigate(~p"/accounts/#{row.account}", @current)}
        href={href(~p"/accounts/#{row.account}", @current)}
      />
      <:nav
        key={:add_account}
        id="side-add-account"
        label="Konto hinzufügen"
        icon="plus"
        section={List.last(@groups)[:label]}
        on_click={JS.push("open_account_dialog")}
      />
      <:nav
        key={:import}
        id="side-import"
        label="Import & Sync"
        icon="refresh-cw"
        navigate={navigate(~p"/import", @current)}
        href={href(~p"/import", @current)}
      />
      <:nav
        key={:settings}
        id="side-settings"
        label="Einstellungen"
        icon="settings"
        dock={false}
        navigate={navigate(~p"/settings", @current)}
        href={href(~p"/settings", @current)}
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
          <:item
            navigate={navigate(~p"/settings", @current)}
            href={href(~p"/settings", @current)}
            icon="settings"
          >
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

  # Zugang & API has a live_session of its own behind the sudo plug; links on the settings pages, which lead into
  # and out of it, load the page.
  defp navigate(_path, :settings), do: nil
  defp navigate(path, _current), do: path

  defp href(path, :settings), do: path
  defp href(_path, _current), do: nil

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
