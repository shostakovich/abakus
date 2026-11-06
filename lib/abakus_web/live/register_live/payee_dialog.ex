defmodule AbakusWeb.RegisterLive.PayeeDialog do
  @moduledoc """
  "Empfänger verwalten" as in the apps (`Abakus.Ledger.Payees`), a modal over the register: the regular payees on the
  left with a search and the filter Aufgeführte / Ausgeblendete / Alle, the shown payee or the selection on the right.
  A click on a name shows one payee, its checkbox adds it to the selection; the selected names read in the order they
  were picked, and "Neuer Name" starts as the last one. Phones get a full-height sheet that goes from the list to the
  detail and back, and "Auswählen" picks several with a bar at the bottom, as on the iPhone. Every change is stored
  at once, and the shown payee is read anew after each, keeping rules still blank.

  The register renders it from Ansicht › "Empfänger verwalten …", on the selected transaction's payee, and updates it
  with `synced: true` when another device changed the budget. It tells its LiveView `{PayeeDialog, :changed}` when
  transactions were renamed, `{PayeeDialog, :show_transactions, name, scheduled?}` for "(in N Buchungen)" and
  `{PayeeDialog, :flash, kind, message}` for a message; `close_payee_dialog` goes to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.Ledger
  alias Abakus.Ledger.{PayeeRenameCondition, Payees}
  alias AbakusWeb.CategoryOptions
  alias AbakusWeb.RegisterLive.EditorFields

  @list_tooltip "Aufgeführte Empfänger erscheinen in der Empfängerliste, werden beim Tippen ergänzt und automatisch " <>
                  "kategorisiert."
  @combine_tooltip "Fasst die ausgewählten Empfänger unter dem Namen aus „Neuer Name“ zusammen. Dazu entstehen " <>
                     "Umbenennungsregeln, damit künftige Buchungen automatisch umbenannt werden."
  @hidden_tooltip "Dieser Empfänger ist ausgeblendet: Er erscheint nicht in der Empfängerliste, wird beim Tippen " <>
                    "nicht ergänzt und nicht automatisch kategorisiert."
  @no_match "Keine Buchungen zum Umbenennen gefunden."
  @no_match_text "Diese Regeln treffen auf keinen Empfänger einer Buchung zu."
  @gone "Den Empfänger gibt es nicht mehr."
  @filters [{"Aufgeführte", "listed"}, {"Ausgeblendete", "hidden"}, {"Alle", "all"}]
  @operators [
    {"enthält", "contains"},
    {"ist", "is"},
    {"beginnt mit", "starts_with"},
    {"endet mit", "ends_with"}
  ]

  @impl true
  def update(%{synced: true}, socket), do: {:ok, refresh(socket, socket.assigns.selection)}

  def update(_assigns, %{assigns: %{rows: _rows}} = socket), do: {:ok, socket}

  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.take(assigns, [:id, :current_scope]))
      |> assign(
        filter: "listed",
        search: "",
        selection: [],
        picking: false,
        pane: :list,
        renaming: false,
        rename_errors: [],
        combine_name: "",
        combine_errors: [],
        rules: [],
        focus: nil,
        initial: assigns.payee_id,
        categories:
          EditorFields.category_options(
            CategoryOptions.build(assigns.current_scope, assigns.today)
          )
      )
      |> load_rows()

    {:ok, opened(socket, assigns.payee_id)}
  end

  defp opened(socket, payee_id) do
    case Enum.find(socket.assigns.rows, &(&1.payee.id == payee_id)) do
      nil ->
        socket

      row ->
        socket
        |> assign(filter: if(row.payee.hidden, do: "all", else: "listed"), pane: :detail)
        |> select([payee_id])
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        shown: shown(assigns.rows, assigns.filter, assigns.search),
        shown_payee: shown_payee(assigns),
        filters: @filters,
        operators: @operators,
        list_tooltip: @list_tooltip,
        combine_tooltip: @combine_tooltip,
        hidden_tooltip: @hidden_tooltip
      )

    ~H"""
    <div id={@id}>
      <.modal
        id="payee-modal"
        show
        title="Empfänger verwalten"
        title_class={@pane == :detail && "max-sm:sr-only"}
        on_cancel={JS.push("close_payee_dialog")}
        class="app-payees"
      >
        <:leading :if={@pane == :detail}>
          <.button
            id="payee-back"
            variant={:ghost}
            size={:sm}
            icon="chevron-left"
            class="sm:hidden"
            phx-click="back"
            phx-target={@myself}
          >
            Empfänger
          </.button>
        </:leading>
        <:trailing :if={@pane == :list}>
          <.button
            id="payee-pick-toggle"
            variant={:ghost}
            size={:sm}
            class="sm:hidden"
            phx-click="toggle_picking"
            phx-target={@myself}
          >
            {if @picking, do: "Fertig", else: "Auswählen"}
          </.button>
        </:trailing>
        <div class="app-payees-body" data-pane={@pane}>
          <section class="app-payees-list" aria-label="Empfänger">
            <form
              id="payee-search"
              role="search"
              phx-change="search"
              phx-submit="search"
              phx-target={@myself}
            >
              <.input
                id="payee-q"
                type="search"
                name="q"
                value={@search}
                label="Empfänger suchen"
                hide_label
                icon="search"
                placeholder="Empfänger suchen"
                class="input-sm"
                autocomplete="off"
                phx-debounce="200"
              />
            </form>
            <.segmented
              id="payee-filter"
              mode={:button}
              value={@filter}
              label="Zeigen"
              size={:sm}
              block
              options={@filters}
              phx-click="filter"
              phx-target={@myself}
            />
            <.list
              :if={@shown != []}
              id="payee-rows"
              size={:compact}
              framed
              class="min-h-0 flex-1"
            >
              <.list_row
                :for={row <- @shown}
                id={"payee-row-#{row.payee.id}"}
                title={row.payee.name}
                selected={row.payee.id in @selection}
                checked={row.payee.id in @selection}
                on_check={JS.push("toggle", value: %{id: row.payee.id}, target: @myself)}
                check_from={if !@picking, do: :sm}
                autofocus={row.payee.id == @initial}
                on_click={
                  JS.push(if(@picking, do: "toggle", else: "show"),
                    value: %{id: row.payee.id},
                    target: @myself
                  )
                }
                trailing_on_phone={:title}
                strong={row.rename_conditions != []}
              >
                <:trailing :if={@filter == "all" and row.payee.hidden}>
                  <span title={@hidden_tooltip}>
                    <.icon name="eye-off" label="Ausgeblendet" class="text-base-content/60" />
                  </span>
                </:trailing>
              </.list_row>
            </.list>
            <p :if={@shown == []} id="payee-rows-empty" class="app-payees-empty">
              {empty_text(@filter, @search)}
            </p>
          </section>
          <section class="app-payees-detail" aria-labelledby="payee-modal-title">
            <p :if={@selection == []} id="payee-prompt" class="app-payees-prompt">
              Empfänger zum Bearbeiten wählen
            </p>
            <.single
              :if={@shown_payee}
              row={@shown_payee}
              renaming={@renaming}
              rename_errors={@rename_errors}
              rules={@rules}
              focus={@focus}
              preview={@preview}
              categories={@categories}
              operators={@operators}
              list_tooltip={@list_tooltip}
              myself={@myself}
            />
            <.multiple
              :if={length(@selection) > 1}
              names={@rows |> selected_names(@selection) |> Enum.reverse()}
              combine_name={@combine_name}
              combine_errors={@combine_errors}
              list_tooltip={@list_tooltip}
              combine_tooltip={@combine_tooltip}
              myself={@myself}
            />
          </section>
        </div>
        <:actions>
          <.selection_bar
            :if={@picking and @pane == :list}
            id="payee-pick-bar"
            inline
            count={length(@selection)}
            class="sm:hidden"
          >
            <:leading>
              <.button
                id="payee-pick-combine"
                variant={:ghost}
                size={:sm}
                disabled={length(@selection) < 2}
                phx-click="combine_pane"
                phx-target={@myself}
              >
                Zusammenfassen
              </.button>
            </:leading>
            <.dropdown
              id="payee-pick-listed"
              label="Aufführen"
              align={:end}
              variant={:ghost}
              chevron={false}
              trigger_class={["btn-sm btn-square", @selection == [] && "btn-disabled"]}
            >
              <:trigger><.icon name="eye" /></:trigger>
              <:item
                id="payee-pick-show"
                icon="eye"
                disabled={@selection == []}
                on_click={JS.push("set_listed", value: %{listed: "true"}, target: @myself)}
              >
                Aufführen und ergänzen
              </:item>
              <:item
                id="payee-pick-hide"
                icon="eye-off"
                disabled={@selection == []}
                on_click={JS.push("set_listed", value: %{listed: "false"}, target: @myself)}
              >
                Ausblenden
              </:item>
            </.dropdown>
          </.selection_bar>
          <.button
            id="payee-close"
            class={@picking and @pane == :list and "max-sm:hidden"}
            phx-click={hide_modal("payee-modal")}
          >
            Schließen
          </.button>
        </:actions>
      </.modal>
      <.combobox_options id="payee-category-list" options={@categories}>
        <:option :let={option}>
          <span class="min-w-0 flex-1 truncate">{option.name}</span>
        </:option>
      </.combobox_options>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :renaming, :boolean, required: true
  attr :rename_errors, :list, required: true
  attr :rules, :list, required: true
  attr :focus, :any, required: true
  attr :preview, :map, required: true
  attr :categories, :list, required: true
  attr :operators, :list, required: true
  attr :list_tooltip, :string, required: true
  attr :myself, :any, required: true

  defp single(assigns) do
    ~H"""
    <div id="payee-single" class="app-payees-form">
      <div class="app-payees-group">
        <div :if={!@renaming} class="app-payees-name-row">
          <h3 id="payee-name" class="truncate text-lg font-semibold" title={@row.payee.name}>
            {@row.payee.name}
          </h3>
          <.button
            id="payee-rename"
            variant={:ghost}
            size={:sm}
            icon="pencil"
            phx-click="start_rename"
            phx-target={@myself}
          >
            Umbenennen
          </.button>
        </div>
        <.form
          :if={@renaming}
          for={%{}}
          id="payee-rename-form"
          class="app-payees-rename"
          phx-submit="rename"
          phx-target={@myself}
        >
          <.input
            id="payee-rename-name"
            name="name"
            value={@row.payee.name}
            label="Name des Empfängers"
            hide_label
            autocomplete="off"
            errors={@rename_errors}
            on_escape="cancel_rename"
            phx-target={@myself}
            phx-mounted={JS.focus()}
          />
          <.button id="payee-rename-cancel" phx-click="cancel_rename" phx-target={@myself}>
            Abbrechen
          </.button>
          <.button id="payee-rename-save" type="submit" variant={:primary}>Sichern</.button>
        </.form>
        <.form
          for={%{}}
          id="payee-listed-form"
          class="app-payees-listed"
          title={@list_tooltip}
          phx-change="listed"
          phx-target={@myself}
        >
          <div class="min-w-0">
            <p>Empfänger aufführen und ergänzen</p>
            <p class="text-sm text-base-content/70">
              (in <.uses count={@row.transaction_count} myself={@myself} />)
            </p>
            <p class="mt-1 text-sm text-base-content/70 sm:hidden">{@list_tooltip}</p>
          </div>
          <.input
            id="payee-listed"
            type="toggle"
            name="listed"
            checked={!@row.payee.hidden}
            label="Empfänger aufführen und ergänzen"
            hide_label
            bare
          />
        </.form>
      </div>
      <.form
        for={%{}}
        id="payee-category-form"
        phx-change="category"
        phx-target={@myself}
      >
        <.combobox
          id="payee-category"
          name="category_id"
          value={@row.payee.last_category_id}
          label="Diesen Empfänger automatisch kategorisieren als:"
          options={@categories}
          options_from="payee-category-list"
          placeholder="Kategorie"
        />
      </.form>
      <div class="app-payees-rules">
        <p id="payee-rules-label" class="text-sm">
          Importierte Buchungen in <b>{@row.payee.name}</b> umbenennen, wenn der Empfänger:
        </p>
        <.form
          :if={@rules != []}
          for={%{}}
          id="payee-rules-form"
          phx-change="rules"
          phx-target={@myself}
        >
          <.field_row :for={rule <- @rules} id={"payee-rule-#{rule.key}"}>
            <.input
              type="select"
              bare
              id={"payee-rule-#{rule.key}-operator"}
              name={"rules[#{rule.key}][operator]"}
              label="Bedingung"
              options={@operators}
              value={rule.operator}
              class="select-sm w-34 max-sm:w-27"
            />
            <.input
              bare
              id={"payee-rule-#{rule.key}-text"}
              name={"rules[#{rule.key}][text]"}
              value={rule.text}
              label="Text im Empfänger"
              errors={rule.errors}
              class="input-sm"
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={@focus == rule.key && JS.focus()}
            />
            <.button
              id={"payee-rule-#{rule.key}-remove"}
              variant={:ghost}
              size={:sm}
              icon="minus"
              icon_only
              label="Regel entfernen"
              phx-click="remove_rule"
              phx-value-key={rule.key}
              phx-target={@myself}
            />
            <.button
              id={"payee-rule-#{rule.key}-add"}
              variant={:ghost}
              size={:sm}
              icon="plus"
              icon_only
              label="Umbenennungsregel hinzufügen"
              class={["max-sm:hidden", rule != List.last(@rules) && "invisible"]}
              disabled={blank?(rule)}
              phx-click="add_rule"
              phx-target={@myself}
            />
          </.field_row>
        </.form>
        <.button
          id="payee-add-rule"
          variant={:ghost}
          size={:sm}
          icon="plus"
          class={["self-start", @rules != [] && "sm:hidden"]}
          disabled={@rules != [] and blank?(List.last(@rules))}
          phx-click="add_rule"
          phx-target={@myself}
        >
          Umbenennungsregel hinzufügen
        </.button>
        <div :if={@rules != []} class="flex justify-end">
          <.button
            id="payee-rename-existing"
            disabled={blank?(List.last(@rules))}
            phx-click={JS.push("rename_existing", value: %{ids: @preview.payee_ids}, target: @myself)}
            {rename_dialog(@preview, @row.payee.name)}
          >
            Bestehende Buchungen umbenennen
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :myself, :any, required: true

  defp uses(%{count: 0} = assigns), do: ~H"0 Buchungen"

  defp uses(assigns) do
    ~H"""
    <button
      id="payee-uses"
      type="button"
      class="link link-primary"
      title="Klicken, um diese Buchungen im Konto zu zeigen"
      phx-click="show_transactions"
      phx-target={@myself}
    >{bookings(@count)}</button>
    """
  end

  attr :names, :list, required: true, doc: "in the order they were selected"
  attr :combine_name, :string, required: true
  attr :combine_errors, :list, required: true
  attr :list_tooltip, :string, required: true
  attr :combine_tooltip, :string, required: true
  attr :myself, :any, required: true

  defp multiple(assigns) do
    ~H"""
    <div id="payee-multiple" class="app-payees-form">
      <div class="app-payees-group">
        <h3 id="payee-multiple-title" class="font-semibold">{length(@names)} Empfänger ausgewählt</h3>
        <p id="payee-multiple-names" class="app-payees-names" title={quoted(@names)}>
          {quoted(@names)}
        </p>
      </div>
      <.form
        for={%{}}
        id="payee-combine-form"
        class="app-payees-group"
        phx-change="combine_name"
        phx-submit="combine"
        phx-target={@myself}
      >
        <p class="text-sm font-semibold" title={@combine_tooltip}>
          Ausgewählte Empfänger zusammenfassen und umbenennen?
        </p>
        <div class="app-payees-combine">
          <.input
            id="payee-combine-name"
            name="name"
            value={@combine_name}
            label="Neuer Name"
            autocomplete="off"
            errors={@combine_errors}
          />
          <.button
            id="payee-combine"
            type="submit"
            variant={:primary}
            disabled={String.trim(@combine_name) == ""}
          >
            Zusammenfassen
          </.button>
        </div>
        <p class="text-sm text-base-content/70 sm:hidden">{@combine_tooltip}</p>
      </.form>
      <div class="app-payees-group" title={@list_tooltip}>
        <p class="text-sm font-semibold">Ausgewählte Empfänger aufführen und ergänzen?</p>
        <div class="flex flex-wrap gap-2">
          <.button
            id="payee-hide-selected"
            phx-click="set_listed"
            phx-value-listed="false"
            phx-target={@myself}
          >
            Ausblenden
          </.button>
          <.button
            id="payee-show-selected"
            phx-click="set_listed"
            phx-value-listed="true"
            phx-target={@myself}
          >
            Aufführen
          </.button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, :search, q)}

  def handle_event("filter", %{"value" => filter}, socket) when filter in ~w(listed hidden all),
    do: {:noreply, assign(socket, :filter, filter)}

  def handle_event("show", %{"id" => id}, socket),
    do: {:noreply, socket |> select([id]) |> assign(:pane, :detail)}

  def handle_event("toggle", %{"id" => id}, socket) do
    selection = socket.assigns.selection

    if id in selection,
      do: {:noreply, select(socket, List.delete(selection, id))},
      else: {:noreply, select(socket, [id | selection])}
  end

  def handle_event("back", _params, %{assigns: %{picking: true}} = socket),
    do: {:noreply, assign(socket, :pane, :list)}

  def handle_event("back", _params, socket),
    do: {:noreply, socket |> select([]) |> assign(:pane, :list)}

  def handle_event("toggle_picking", _params, socket),
    do: {:noreply, socket |> select([]) |> update(:picking, &(!&1))}

  def handle_event("combine_pane", _params, socket) do
    if length(socket.assigns.selection) > 1,
      do: {:noreply, assign(socket, :pane, :detail)},
      else: {:noreply, socket}
  end

  def handle_event("start_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: true, rename_errors: [])}

  def handle_event("cancel_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: false, rename_errors: [])}

  def handle_event("rename", %{"name" => name}, socket) do
    with %{payee: payee} <- shown_payee(socket.assigns),
         trimmed when trimmed not in ["", payee.name] <- String.trim(name) do
      case Payees.rename(socket.assigns.current_scope, payee, trimmed) do
        {:ok, renamed} ->
          {:noreply, socket |> assign(renaming: false) |> refresh([renamed.id]) |> changed()}

        {:error, :not_found} ->
          {:noreply, gone(socket)}

        {:error, changeset} ->
          {:noreply, assign(socket, :rename_errors, errors(changeset))}
      end
    else
      _unchanged -> {:noreply, assign(socket, renaming: false, rename_errors: [])}
    end
  end

  def handle_event("listed", %{"listed" => listed}, socket) do
    case shown_payee(socket.assigns) do
      nil -> {:noreply, socket}
      %{payee: payee} -> {:noreply, set_listed(socket, [payee.id], listed)}
    end
  end

  def handle_event("set_listed", %{"listed" => listed}, socket),
    do: {:noreply, set_listed(socket, socket.assigns.selection, listed)}

  def handle_event("category", %{"category_id" => id}, socket) do
    category_id = if id == "", do: nil, else: id

    with %{payee: payee} <- shown_payee(socket.assigns),
         true <- category_id != payee.last_category_id do
      case Ledger.update_payee(socket.assigns.current_scope, payee, %{
             last_category_id: category_id
           }) do
        {:ok, _payee} -> {:noreply, refresh(socket, socket.assigns.selection)}
        {:error, :not_found} -> {:noreply, gone(socket)}
        {:error, _changeset} -> {:noreply, socket}
      end
    else
      _unchanged -> {:noreply, socket}
    end
  end

  def handle_event("rules", %{"rules" => params}, socket) do
    rules =
      Enum.map(socket.assigns.rules, fn rule ->
        case params[Integer.to_string(rule.key)] do
          %{} = typed ->
            %{rule | operator: typed["operator"] || rule.operator, text: typed["text"] || ""}

          nil ->
            rule
        end
      end)

    {:noreply, store_rules(socket, rules)}
  end

  def handle_event("add_rule", _params, socket) do
    rules = socket.assigns.rules

    if rules == [] or not blank?(List.last(rules)) do
      rule = new_rule(nil, "contains", "")
      {:noreply, assign(socket, rules: rules ++ [rule], focus: rule.key)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_rule", %{"key" => key}, socket) do
    rules = Enum.reject(socket.assigns.rules, &(Integer.to_string(&1.key) == key))
    {:noreply, store_rules(socket, rules)}
  end

  def handle_event("rename_existing", params, socket) do
    case shown_payee(socket.assigns) do
      nil -> {:noreply, socket}
      %{payee: payee} -> {:noreply, rename_existing(socket, payee, List.wrap(params["ids"]))}
    end
  end

  def handle_event("combine_name", %{"name" => name}, socket),
    do: {:noreply, assign(socket, combine_name: name, combine_errors: [])}

  def handle_event("combine", %{"name" => name}, socket) do
    case Payees.combine(socket.assigns.current_scope, socket.assigns.selection, name) do
      {:ok, nil} ->
        {:noreply, gone(socket)}

      {:ok, combined} ->
        {:noreply,
         socket
         |> refresh([combined.id])
         |> assign(picking: false, pane: :detail)
         |> changed()}

      {:error, changeset} ->
        {:noreply, assign(socket, combine_name: name, combine_errors: errors(changeset))}
    end
  end

  def handle_event("show_transactions", _params, socket) do
    with %{payee: payee, scheduled: scheduled} <- shown_payee(socket.assigns),
         do: send(self(), {__MODULE__, :show_transactions, payee.name, scheduled})

    {:noreply, socket}
  end

  # The confirm dialog carries the payees it showed, so only what was asked about is renamed.
  defp rename_existing(socket, payee, ids) do
    scope = socket.assigns.current_scope

    case Payees.rename_preview(scope, payee) do
      {:ok, %{payee_ids: [_ | _]}} when ids != [] ->
        case Payees.apply_rename_rules(scope, payee, ids) do
          {:ok, _payee} -> socket |> refresh(socket.assigns.selection) |> changed()
          {:error, :changed} -> reload_shown(socket)
          {:error, :not_found} -> gone(socket)
        end

      {:ok, _preview} ->
        reload_shown(socket)

      {:error, :not_found} ->
        gone(socket)
    end
  end

  defp set_listed(socket, ids, listed) do
    :ok = Payees.set_hidden(socket.assigns.current_scope, ids, listed != "true")
    refresh(socket, socket.assigns.selection)
  end

  defp changed(socket) do
    send(self(), {__MODULE__, :changed})
    socket
  end

  defp flash(socket, kind, message) do
    send(self(), {__MODULE__, :flash, kind, message})
    socket
  end

  defp gone(socket), do: socket |> flash(:error, @gone) |> refresh(socket.assigns.selection)

  defp load_rows(socket),
    do: assign(socket, :rows, Payees.list(socket.assigns.current_scope))

  # Reads the payees anew; a shown payee that stays keeps its blank rules, one that is gone leaves the selection.
  defp refresh(socket, selection) do
    before = socket.assigns.selection
    socket = socket |> load_rows() |> select(selection)

    if socket.assigns.selection == before, do: reload_shown(socket), else: socket
  end

  defp select(socket, selection) do
    %{selection: before, rows: rows} = socket.assigns
    selection = Enum.filter(selection, fn id -> Enum.any?(rows, &(&1.payee.id == id)) end)

    socket =
      if selection == before,
        do: socket,
        else: assign(socket, selection: selection, renaming: false, rename_errors: [])

    cond do
      length(selection) == 1 and selection != before ->
        load_shown(socket)

      length(selection) > 1 and length(before) < 2 ->
        assign(socket,
          combine_name: hd(selected_names(rows, selection)),
          combine_errors: []
        )

      true ->
        socket
    end
  end

  defp load_shown(socket) do
    case shown_payee(socket.assigns) do
      nil ->
        socket

      row ->
        rules = for condition <- row.rename_conditions, do: rule(condition, nil)

        socket
        |> assign(rules: rules, focus: nil)
        |> assign_preview(row.payee)
    end
  end

  defp reload_shown(socket) do
    case shown_payee(socket.assigns) do
      nil ->
        socket

      row ->
        before = socket.assigns.rules
        keys = Map.new(before, &{&1.id, &1.key})

        rules =
          for(condition <- row.rename_conditions, do: rule(condition, keys[condition.id])) ++
            Enum.filter(before, &(is_nil(&1.id) and blank?(&1)))

        socket
        |> assign(:rules, rules)
        |> assign_preview(row.payee)
    end
  end

  defp rule(condition, key),
    do: new_rule(condition.id, Atom.to_string(condition.operator), condition.text, key)

  defp new_rule(id, operator, text, key \\ nil),
    do: %{
      key: key || System.unique_integer([:positive]),
      id: id,
      operator: operator,
      text: text,
      errors: []
    }

  defp store_rules(socket, rules) do
    case shown_payee(socket.assigns) do
      nil ->
        socket

      %{payee: payee} ->
        conditions = Enum.map(rules, &Map.take(&1, [:id, :operator, :text]))
        rules = Enum.map(rules, &%{&1 | errors: []})

        case Payees.put_rename_conditions(socket.assigns.current_scope, payee, conditions) do
          {:ok, stored} ->
            socket
            |> assign(rules: stored_ids(rules, Enum.map(stored, & &1.id)), focus: nil)
            |> load_rows()
            |> assign_preview(payee)

          {:error, :not_found} ->
            gone(socket)

          {:error, changeset} ->
            assign(socket, :rules, with_errors(rules, changeset))
        end
    end
  end

  defp with_errors(rules, changeset) do
    text = Ecto.Changeset.get_field(changeset, :text)
    failed = Enum.find(rules, &(&1.text == text))
    messages = for {:text, error} <- changeset.errors, do: error

    Enum.map(rules, &if(&1 == failed, do: %{&1 | errors: messages}, else: &1))
  end

  # Blank rules are not stored, so the stored ones match the others in order.
  defp stored_ids([], _ids), do: []
  defp stored_ids([rule | rules], []), do: [%{rule | id: nil} | stored_ids(rules, [])]

  defp stored_ids([rule | rules], [id | ids] = all) do
    if blank?(rule),
      do: [%{rule | id: nil} | stored_ids(rules, all)],
      else: [%{rule | id: id} | stored_ids(rules, ids)]
  end

  defp assign_preview(socket, payee) do
    preview =
      case Payees.rename_preview(socket.assigns.current_scope, payee) do
        {:ok, preview} -> preview
        {:error, :not_found} -> %{transaction_count: 0, payee_names: [], payee_ids: []}
      end

    assign(socket, :preview, preview)
  end

  defp shown_payee(%{selection: [id], rows: rows}), do: Enum.find(rows, &(&1.payee.id == id))
  defp shown_payee(_assigns), do: nil

  defp shown(rows, filter, search) do
    search = search |> String.trim() |> String.downcase()

    Enum.filter(rows, fn %{payee: payee} ->
      listed?(payee, filter) and
        (search == "" or String.contains?(String.downcase(payee.name), search))
    end)
  end

  defp listed?(payee, "listed"), do: not payee.hidden
  defp listed?(payee, "hidden"), do: payee.hidden
  defp listed?(_payee, "all"), do: true

  defp selected_names(rows, selection) do
    by_id = Map.new(rows, &{&1.payee.id, &1.payee.name})
    for id <- selection, name = by_id[id], do: name
  end

  defp quoted(names), do: Enum.map_join(names, ", ", &"„#{&1}“")

  defp blank?(rule), do: PayeeRenameCondition.blank?(rule.text)

  defp bookings(1), do: "1 Buchung"
  defp bookings(count), do: "#{count} Buchungen"

  defp empty_text(_filter, search) when search != "" do
    if String.trim(search) == "",
      do: "Keine Empfänger",
      else: "Keine Empfänger mit „#{String.trim(search)}“"
  end

  defp empty_text("hidden", _search), do: "Keine ausgeblendeten Empfänger"
  defp empty_text(_filter, _search), do: "Keine Empfänger"

  defp rename_dialog(%{payee_ids: []}, _name),
    do: %{alert: @no_match, alert_text: @no_match_text}

  defp rename_dialog(%{transaction_count: count, payee_names: names}, name) do
    %{
      confirm:
        if(count == 0,
          do: "Empfänger in „#{name}“ umbenennen?",
          else: "Bei #{bookings(count)} wird der Empfänger in „#{name}“ umbenannt:"
        ),
      confirm_text: "Betroffene Empfänger: #{quoted(names)}",
      confirm_label: "Umbenennen"
    }
  end

  defp errors(changeset) do
    for {_field, {message, opts}} <- changeset.errors, do: {message, opts}
  end
end
