defmodule AbakusWeb.Depot.SecurityDialog do
  @moduledoc """
  The edit dialog of a security, on the securities page and on its own page: where its prices
  come from, its ISIN and whether it is retired, with what saving does (`SecurityChanges`) and what
  arrived so far. A new ISIN is looked up at Yahoo in the background, to show whose it is.

  Saving or cancelling patches to `return_to`, deleting goes to `deleted_to` (patched to when it
  is `return_to`'s page, else navigated to). Saving sends `{SecurityDialog, :saved}` to the page. `params` start the form, e.g. to bring a retired
  security back. `title` replaces the security's name as the dialog's title. Passing the security
  again, e.g. after a fetch, keeps what is typed.
  """
  use AbakusWeb, :live_component

  alias Abakus.Depot.{MarketData, Receipts, Securities}
  alias Abakus.{Format, LocalTime}
  alias AbakusWeb.Depot.Format, as: DepotFormat
  alias AbakusWeb.Depot.{NewSecurity, SecurityChanges, SecurityRow}

  @feeds [{"Yahoo", "yahoo"}, {"Ohne Kursabruf", "manual"}]

  @no_fund_data "DivvyDiary hat keine Fondsdaten zu dieser ISIN."

  @delete_text "Kurse, Zusammensetzung, Dividenden von DivvyDiary und Zuordnungen werden mit gelöscht."

  @impl true
  def update(%{security: security} = assigns, %{assigns: %{form: form}} = socket) do
    socket = assign(socket, Map.drop(assigns, [:params, :security]))

    if security == socket.assigns.security,
      do: {:ok, socket},
      else: {:ok, socket |> assign(:security, security) |> refresh(form.params)}
  end

  def update(assigns, socket) do
    %{security: security, current_scope: scope} = assigns
    params = Map.get(assigns, :params, %{})
    usage = Securities.usage(scope, security)

    socket
    |> assign(assigns)
    |> assign(
      usage: usage,
      lookup: nil,
      isin_left: false,
      available: MarketData.divvy_diary_available?()
    )
    |> refresh(params)
    |> then(&{:ok, &1})
  end

  defp refresh(socket, params) do
    %{current_scope: scope, security: security} = socket.assigns

    socket
    |> assign(:fetched_at, Securities.divvy_diary_fetched_at(scope, security))
    |> put_params(params)
  end

  defp put_params(socket, params) do
    %{security: security, usage: usage, isin_left: left} = socket.assigns
    action = if params == %{}, do: nil, else: :validate

    changeset =
      security
      |> Securities.change_security(params)
      |> Map.put(:action, action)
      |> NewSecurity.hold_isin_errors(left)

    assign(socket,
      form: edit_form(changeset),
      changes: SecurityChanges.of(security, params, usage)
    )
  end

  defp edit_form(changeset), do: to_form(changeset, as: :security)

  @impl true
  def render(assigns) do
    %{security: security, form: form, changes: changes} = assigns
    yahoo? = to_string(form[:quote_feed].value) == "yahoo"
    source_help = SecurityChanges.source_help(changes)
    assigns = assign(assigns, :retired?, Ecto.Changeset.get_field(form.source, :retired))

    {isin_help, isin_tone} =
      if Keyword.has_key?(form.errors, :isin), do: {nil, nil}, else: isin_help(assigns)

    {symbol_help, symbol_tone} = symbol_help(security, source_help)
    {retired_help, retired_tone} = SecurityChanges.retired_help(changes)

    assigns =
      assign(assigns,
        yahoo?: yahoo?,
        isin_help: isin_help,
        isin_tone: isin_tone,
        feed_help: if(!yahoo?, do: source_help),
        symbol_help: symbol_help,
        symbol_tone: symbol_tone,
        retired_help: retired_help,
        retired_tone: retired_tone,
        title: assigns[:title] || security.name,
        delete_text: @delete_text,
        feeds: @feeds
      )
      |> assign(other_listing(assigns, yahoo?))

    ~H"""
    <div>
      <.modal
        id="edit-security-dialog"
        show
        title={@title}
        placement={:top}
        on_cancel={JS.patch(@return_to)}
      >
        <.form
          for={@form}
          id="security-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <.input
            field={@form[:isin]}
            label="ISIN"
            identifier
            size="13"
            placeholder="XX0000000000"
            phx-debounce="300"
            phx-blur="leave_isin"
            phx-target={@myself}
            help={@isin_help}
            help_tone={@isin_tone}
          />
          <div :if={@take_symbol}>
            <.button
              id="security-take-symbol"
              size={:sm}
              phx-click="take_symbol"
              phx-target={@myself}
            >
              Symbol {@take_symbol} übernehmen
            </.button>
          </div>
          <.input
            field={@form[:quote_feed]}
            type="select"
            label="Kursquelle"
            options={@feeds}
            help={@feed_help}
            help_tone={@feed_help && :warning}
          />
          <.input
            :if={@yahoo?}
            field={@form[:symbol]}
            label="Yahoo-Symbol"
            placeholder="XYZ.DE"
            autocomplete="off"
            spellcheck="false"
            autocapitalize="characters"
            phx-debounce="300"
            help={@symbol_help}
            help_tone={@symbol_tone}
          />
          <.input
            field={@form[:retired]}
            type="toggle"
            label="Ausgemustert"
            help={@retired_help}
            help_tone={@retired_tone}
          />
          <.action_bar class="mt-4">
            <:secondary>
              <.button
                :if={!delete_reason(@usage)}
                id="security-delete"
                variant={:danger_outline}
                icon="trash-2"
                phx-click="delete"
                phx-target={@myself}
                confirm={"„#{@security.name}“ löschen?"}
                confirm_text={@delete_text}
              >
                Löschen
              </.button>
              <p
                :if={delete_reason(@usage)}
                id="security-delete-reason"
                class="text-sm text-base-content/70"
              >
                {delete_reason(@usage)}
              </p>
            </:secondary>
            <.button patch={@return_to}>Abbrechen</.button>
            <.button
              id="security-save"
              type="submit"
              variant={:primary}
              confirm={@confirm && @confirm.question}
              confirm_text={@confirm && @confirm.text}
              confirm_label={@confirm && @confirm.label}
              phx-disable-with="Speichert …"
            >
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  defp delete_reason(%{booked: true}), do: "Hat Buchungen, nicht löschbar."
  defp delete_reason(%{benchmark: true}), do: "Ist eine Benchmark, nicht löschbar."
  defp delete_reason(%{assigned: true}), do: "Von anderen zugeordnet, nicht löschbar."
  defp delete_reason(_usage), do: nil

  defp isin_help(%{changes: %{isin: isin} = changes} = assigns) when isin in [:added, :changed] do
    lookup = shown_lookup(assigns)
    consequence = SecurityChanges.isin_help(changes, assigns.available)

    case Enum.reject([lookup, consequence], &is_nil/1) do
      [] ->
        {nil, nil}

      parts ->
        {Enum.map_join(parts, " ", &elem(&1, 0)),
         if(Enum.any?(parts, &(elem(&1, 1) == :warning)), do: :warning)}
    end
  end

  defp isin_help(%{changes: %{isin: :removed} = changes, available: available}),
    do: SecurityChanges.isin_help(changes, available)

  defp isin_help(%{retired?: true}), do: {nil, nil}

  defp isin_help(%{security: security, available: available, fetched_at: fetched_at}) do
    cond do
      security.isin in [nil, ""] -> {if(available, do: SecurityChanges.fund_data_help()), nil}
      answer = available && divvy_diary_answer(security) -> answer
      line = divvy_diary_line(security, fetched_at) -> {line, nil}
      available -> {SecurityChanges.fund_data_help(), nil}
      true -> {nil, nil}
    end
  end

  defp divvy_diary_answer(%{divvy_diary_error: error}) when is_binary(error),
    do: {error, :warning}

  defp divvy_diary_answer(%{divvy_diary_unknown: true}), do: {@no_fund_data, nil}
  defp divvy_diary_answer(_security), do: nil

  defp shown_lookup(assigns) do
    if result = lookup_result(assigns),
      do: SecurityChanges.yahoo_name(result, assigns.security.name)
  end

  defp other_listing(%{form: form, changes: changes} = assigns, yahoo?) do
    other = other_security(assigns)
    symbol = Ecto.Changeset.get_field(form.source, :symbol)
    taken? = other != nil and yahoo? and symbol == other.symbol
    kept = if yahoo? and changes.source == nil and not taken?, do: symbol

    %{
      take_symbol: if(other && !taken?, do: other.symbol),
      confirm: SecurityChanges.confirmation(changes, other && other.name, kept)
    }
  end

  defp other_security(%{changes: %{isin: isin}} = assigns) when isin in [:added, :changed],
    do: assigns |> lookup_result() |> SecurityChanges.other_security(assigns.security.name)

  defp other_security(_assigns), do: nil

  defp lookup_result(%{lookup: {isin, result}, form: form}) do
    if SecurityChanges.typed_isin(form[:isin].value) == isin, do: result
  end

  defp lookup_result(_assigns), do: nil

  defp divvy_diary_line(security, fetched_at) do
    ter = Securities.Security.ter(security)
    fund_size = Securities.Security.fund_size(security)

    parts = [
      ter && "TER #{DepotFormat.ter(ter)}",
      fund_size && "Fondsgröße #{DepotFormat.fund_size(fund_size, security.currency)}",
      fetched_at && "Stand #{fetched_on(fetched_at)}"
    ]

    if Enum.any?(parts), do: "DivvyDiary: " <> join_meta(parts)
  end

  defp fetched_on(at) do
    date = LocalTime.date(at)
    Format.date(date, year: date.year != LocalTime.today().year)
  end

  defp symbol_help(_security, source_help) when is_binary(source_help),
    do: {source_help, :warning}

  defp symbol_help(%{retired: false, fetch_error: error}, nil) when is_binary(error),
    do: {error, :warning}

  defp symbol_help(%{latest_close: close} = security, nil) when is_integer(close) do
    date = SecurityRow.quote_date(security, LocalTime.today())
    {"Letzter Kurs #{SecurityRow.price(security)} vom #{date}", nil}
  end

  defp symbol_help(_security, nil), do: {nil, nil}

  @impl true
  def handle_event("validate", %{"security" => params} = event, socket) do
    {:noreply, socket |> put_params(params) |> maybe_look_up(event["_target"])}
  end

  def handle_event("leave_isin", _params, socket) do
    {:noreply, socket |> assign(:isin_left, true) |> put_params(socket.assigns.form.params)}
  end

  def handle_event("take_symbol", _params, socket) do
    case other_security(socket.assigns) do
      %{symbol: symbol} ->
        params =
          Map.merge(socket.assigns.form.params, %{"quote_feed" => "yahoo", "symbol" => symbol})

        {:noreply, put_params(socket, params)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"security" => params}, socket) do
    %{security: before, current_scope: scope} = socket.assigns

    case Securities.update_security(scope, before, params) do
      {:ok, updated} ->
        if refetch_prices?(before, updated), do: MarketData.fetch_in_background(updated)
        divvy_diary? = ask_divvy_diary?(before, updated)
        if divvy_diary?, do: MarketData.fetch_divvy_diary_in_background(updated)
        if updated.isin != before.isin, do: Receipts.recheck(scope)
        send(self(), {__MODULE__, :saved})

        message =
          if divvy_diary?, do: "Gespeichert. DivvyDiary wird gefragt …", else: "Gespeichert."

        {:noreply,
         socket |> put_flash(:info, message) |> push_patch(to: socket.assigns.return_to)}

      {:error, changeset} ->
        changes = SecurityChanges.of(before, params, socket.assigns.usage)
        {:noreply, assign(socket, form: edit_form(changeset), changes: changes)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{security: security, current_scope: scope, usage: usage} = socket.assigns

    case Securities.delete_security(scope, security) do
      {:ok, security} ->
        Receipts.recheck(scope)
        socket = put_flash(socket, :info, "„#{security.name}“ gelöscht.")
        {:noreply, leave(socket, socket.assigns.deleted_to)}

      {:error, :booked} ->
        {:noreply, assign(socket, :usage, %{usage | booked: true})}

      {:error, :benchmark} ->
        {:noreply, assign(socket, :usage, %{usage | benchmark: true})}

      {:error, :assigned} ->
        {:noreply, assign(socket, :usage, %{usage | assigned: true})}
    end
  end

  defp leave(%{assigns: %{return_to: return_to}} = socket, deleted_to) do
    if URI.parse(return_to).path == URI.parse(deleted_to).path,
      do: push_patch(socket, to: deleted_to),
      else: push_navigate(socket, to: deleted_to)
  end

  defp maybe_look_up(socket, ["security", "isin"]) do
    %{form: form, lookup: lookup} = socket.assigns
    isin = SecurityChanges.typed_isin(form[:isin].value)

    cond do
      socket.assigns.changes.isin not in [:added, :changed] -> socket
      Keyword.has_key?(form.source.errors, :isin) -> socket
      match?({^isin, _result}, lookup) -> socket
      true -> look_up(socket, isin)
    end
  end

  defp maybe_look_up(socket, _target), do: socket

  defp look_up(socket, isin) do
    socket
    |> assign(:lookup, {isin, :searching})
    |> start_async(:lookup, fn -> NewSecurity.lookup(isin) end)
  end

  @impl true
  def handle_async(:lookup, {:ok, {isin, result}}, %{assigns: %{lookup: {isin, _}}} = socket) do
    shown =
      case result do
        {:ok, found} -> {:ok, Map.take(found, [:name, :symbol])}
        {:error, reason} -> {:error, MarketData.lookup_error(reason)}
      end

    {:noreply, assign(socket, :lookup, {isin, shown})}
  end

  def handle_async(:lookup, {:exit, _reason}, %{assigns: %{lookup: {isin, :searching}}} = socket),
    do:
      {:noreply, assign(socket, :lookup, {isin, {:error, MarketData.lookup_error(:unreachable)}})}

  def handle_async(:lookup, _stale, socket), do: {:noreply, socket}

  defp refetch_prices?(before, updated) do
    updated.quote_feed == :yahoo and not updated.retired and
      ({before.quote_feed, before.symbol} != {:yahoo, updated.symbol} or back?(before, updated))
  end

  defp ask_divvy_diary?(before, updated) do
    updated.isin != nil and not updated.retired and
      (updated.isin != before.isin or back?(before, updated)) and
      MarketData.divvy_diary_available?()
  end

  defp back?(before, updated), do: before.retired and not updated.retired
end
