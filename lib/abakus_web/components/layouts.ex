defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  alias Abakus.Names
  alias AbakusWeb.{AccountGroups, Format}

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current, :atom, default: nil, values: [nil, :budget, :accounts, :all_accounts, :settings]

  attr :account_groups, :list,
    default: [],
    doc: "from `AbakusWeb.AccountGroups`; the sidebar lists the open ones"

  attr :account_id, :integer, default: nil, doc: "the account whose register is shown"

  attr :account_dialog, :map,
    default: nil,
    doc: "the open account form from `AbakusWeb.AccountDialog`, if any"

  slot :inner_block, required: true

  @doc """
  Signed-in pages: a dark sidebar as in YNAB, collapsible to an icon rail (remembered per device by `SideToggle`);
  phones get a header instead.
  """
  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2 app-skip" href="#main">Zum Inhalt springen</a>

    <aside class="app-side d-none d-lg-flex flex-column" data-bs-theme="dark">
      <div class="dropdown pt-3 pb-2" phx-click-away={hide_dropdown("#side-menu", "#side-brand")}>
        <button
          type="button"
          id="side-brand"
          class="btn w-100 text-start d-flex align-items-center gap-2 border-0 text-reset app-side-brand"
          aria-expanded="false"
          aria-controls="side-menu"
          title={"Abakus · #{@current_scope.user.email}"}
          phx-click={toggle_dropdown("#side-menu", "#side-brand")}
        >
          <img src={~p"/images/icon.svg"} alt="" width="30" height="30" />
          <span class="me-auto lh-sm app-side-text app-min-w-0">
            <span class="d-block fw-bold">Abakus</span>
            <span class="d-block small opacity-75 text-truncate">{@current_scope.user.email}</span>
          </span>
          <.icon name="down" class="app-icon-sm app-side-text" />
        </button>
        <ul id="side-menu" class="dropdown-menu" data-bs-popper="static">
          <li><.link class="dropdown-item" href={~p"/users/settings"}>Einstellungen</.link></li>
          <li><hr class="dropdown-divider" /></li>
          <li>
            <.link
              id="log-out"
              class="dropdown-item"
              href={~p"/users/log-out"}
              method="delete"
              title={@current_scope.user.email}
            >
              Abmelden
            </.link>
          </li>
        </ul>
      </div>
      <nav class="nav flex-column gap-1" aria-label="Hauptnavigation">
        <.side_links items={main_items()} current={@current} />
      </nav>
      <div class="flex-grow-1 mt-3">
        <.side_accounts
          groups={AccountGroups.open(@account_groups)}
          current={@current}
          account_id={@account_id}
        />
        <button
          type="button"
          id="side-add-account"
          class="btn btn-sm w-100 my-2 app-side-btn app-side-text"
          phx-click="open_account_dialog"
        >
          + Konto hinzufügen
        </button>
      </div>
      <nav class="nav flex-column pt-2 border-top" aria-label="Weitere">
        <.side_links items={more_items()} current={@current} />
      </nav>
      <div class="d-flex justify-content-end py-2">
        <button
          type="button"
          id="side-toggle"
          class="btn btn-sm app-side-toggle"
          aria-label="Seitenleiste einklappen"
          title="Seitenleiste einklappen"
          phx-hook="SideToggle"
          phx-update="ignore"
        >
          <.icon name="sidebar" />
        </button>
      </div>
    </aside>

    <header class="d-flex d-lg-none flex-wrap align-items-center gap-2 px-3 pt-3">
      <.link
        class="fw-bold fs-5 text-decoration-none text-body me-auto d-flex align-items-center gap-2"
        {nav_link(~p"/", @current)}
      >
        <img src={~p"/images/icon.svg"} alt="" width="26" height="26" /> Abakus
      </.link>
      <nav aria-label="Hauptnavigation">
        <ul class="nav nav-pills">
          <li :for={{key, label, _icon, path} <- phone_items() ++ more_items()} class="nav-item">
            <.link
              class={["nav-link", phone_current(@current) == key && "active"]}
              aria-current={phone_current(@current) == key && "page"}
              {nav_link(path, @current)}
            >
              {label}
            </.link>
          </li>
        </ul>
      </nav>
      <.link href={~p"/users/log-out"} method="delete" class="btn btn-sm btn-outline-secondary">
        Abmelden
      </.link>
    </header>

    <main class="app container-fluid px-3" id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>

    <.live_component
      :if={@account_dialog}
      module={AbakusWeb.AccountDialog}
      id="account-dialog"
      account={@account_dialog.account}
      balance={@account_dialog.balance}
    />
    """
  end

  attr :items, :list, required: true
  attr :current, :atom, required: true

  defp side_links(assigns) do
    ~H"""
    <.link
      :for={{key, label, icon, path} <- @items}
      class={["nav-link", @current == key && "active"]}
      aria-current={@current == key && "page"}
      title={label}
      {nav_link(path, @current)}
    >
      <.icon name={icon} /><span class="app-side-text">{label}</span>
    </.link>
    """
  end

  attr :groups, :list, required: true
  attr :current, :atom, required: true
  attr :account_id, :integer, required: true

  defp side_accounts(assigns) do
    ~H"""
    <section :for={group <- @groups} id={"side-group-#{group.key}"} aria-label={group.label}>
      <div class="d-flex justify-content-between gap-2 mt-2 mb-1 app-side-h">
        <span>{group.label}</span>
        <span class={["app-q", group.balance < 0 && "app-neg"]}>{Format.amount(group.balance)}</span>
      </div>
      <nav class="nav flex-column">
        <.link
          :for={row <- group.rows}
          id={"side-account-#{row.account.id}"}
          class={["nav-link app-acc", row.account.id == @account_id && "active"]}
          aria-current={row.account.id == @account_id && "page"}
          title={"#{row.account.name} · #{Format.euros(row.balance)}"}
          {nav_link(~p"/accounts/#{row.account}", @current)}
        >
          <.account_name name={row.account.name} />
          <span
            :if={row.unapproved > 0}
            class="badge rounded-pill text-bg-primary"
            title={"#{row.unapproved} zu bestätigen"}
          >
            {row.unapproved}
          </span>
          <span class={["app-bal", row.balance < 0 && "app-neg"]}>{Format.amount(row.balance)}</span>
        </.link>
      </nav>
    </section>
    """
  end

  attr :name, :string, required: true

  # The leading emoji in a column of its own; the icon rail keeps only it, or the first letter of a name without.
  defp account_name(assigns) do
    assigns = assign(assigns, :parts, Names.split_emoji(assigns.name))

    ~H"""
    <span :if={elem(@parts, 0)} class="app-acc-e" aria-hidden="true">{elem(@parts, 0)}</span>
    <span :if={!elem(@parts, 0)} class="app-acc-e app-acc-initial" aria-hidden="true">
      {String.first(@name)}
    </span>
    <span class="app-acc-name">{elem(@parts, 1)}</span>
    """
  end

  # Wide screens list the accounts in the sidebar and lead to all of them, as YNAB does; phones have no sidebar and
  # lead to the account list.
  defp main_items,
    do: [
      {:budget, "Budget", "budget", ~p"/"},
      {:all_accounts, "Alle Konten", "bank", ~p"/accounts/all"}
    ]

  defp phone_items,
    do: [{:budget, "Budget", "budget", ~p"/"}, {:accounts, "Konten", "bank", ~p"/accounts"}]

  defp phone_current(:all_accounts), do: :accounts
  defp phone_current(current), do: current

  defp more_items, do: [{:settings, "Einstellungen", "gear", ~p"/users/settings"}]

  # The settings have a live_session of their own behind the sudo plug, so links into and out
  # of them load the page.
  defp nav_link(path, current) do
    if path == ~p"/users/settings" or current == :settings,
      do: [href: path],
      else: [navigate: path]
  end

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main class="container px-3 py-5 app-auth" id="main">
      <h1 class="h3 fw-bold text-center mb-4">Abakus</h1>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  @doc "Light, dark or the device's setting; remembered per device by the `ThemeSwitch` hook."
  def theme_switch(assigns) do
    ~H"""
    <div
      id="theme-switch"
      class="btn-group btn-group-sm"
      role="group"
      aria-label="Farbschema"
      phx-hook="ThemeSwitch"
      phx-update="ignore"
    >
      <%= for {value, label} <- [{"light", "Hell"}, {"dark", "Dunkel"}, {"auto", "Auto"}] do %>
        <input type="radio" class="btn-check" name="theme" id={"theme-#{value}"} value={value} />
        <label class="btn btn-outline-primary" for={"theme-#{value}"}>{label}</label>
      <% end %>
    </div>
    """
  end
end
