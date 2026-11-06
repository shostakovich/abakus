defmodule AbakusWeb.RegisterLive.ScheduledDialog do
  @moduledoc """
  The dialog „Geplante Buchung“ (on phones a sheet from the bottom), for a new scheduled transaction and an existing
  one alike: Konto and Betrag, Empfänger (transfers too), Kategorie and Memo, a split's parts with the transaction
  editor's fields (`EditorFields`, `EditorState`), then Nächstes Datum and Wiederholen. Wiederholen offers Einmalig,
  Monatlich, Jährlich and Eigene; Eigene adds „Alle“ with a number from 1 to 99 and Wochen or Monate (a segmented
  control, on phones a select), and "Danach" lists the three dates after the next one as they change. Errors stand
  next to their field.

  New ones go to an account that takes entries (`Abakus.Ledger.Account.takes_entries?/1`), which the Konto field
  offers, besides the account an existing one has; transfers leave out the shared-expenses account. Tells its
  LiveView `{ScheduledDialog, :done, message}` once saved or deleted; `close_scheduled_dialog` goes to the LiveView
  itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.Format
  alias Abakus.Ledger.{Scheduled, ScheduledTransaction}
  alias AbakusWeb.RegisterLive.{EditorFields, EditorState, TransactionEditor}
  alias AbakusWeb.TransactionForm

  import EditorFields,
    only: [amount_field: 1, category_cell: 1, option_lists: 1, parts: 1, payee_combo: 1]

  @repeats [
    {"Einmalig", "once"},
    {"Monatlich", "monthly"},
    {"Jährlich", "yearly"},
    {"Eigene", "custom"}
  ]
  @units [{"Wochen", "week"}, {"Monate", "month"}]
  @fields [:account_id, :amount, :payee_id, :category_id, :memo, :next_date, :repeat_every]

  @impl true
  def render(assigns) do
    assigns =
      assign(EditorFields.assign_options(assigns),
        repeats: @repeats,
        units: @units,
        following: following(assigns.params)
      )

    ~H"""
    <div id={@id}>
      <.modal
        id="scheduled-modal"
        show
        title="Geplante Buchung"
        placement={:top}
        on_cancel={JS.push("close_scheduled_dialog")}
      >
        <.form
          for={%{}}
          id="sched-form"
          class="flex flex-col gap-1"
          phx-change="change"
          phx-submit="save"
          phx-target={@myself}
        >
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              id="sched-account"
              type="select"
              name="transaction[account_id]"
              value={@params["account_id"]}
              options={EditorFields.account_options(@accounts, kept_accounts(@scheduled))}
              label="Konto"
              errors={errors(@errors, :account_id)}
            />
            <.amount_field
              prefix="sched"
              params={@params}
              target={@myself}
              errors={errors(@errors, :amount)}
            />
          </div>
          <.payee_combo
            id="sched-payee"
            prefix="sched"
            side={@main}
            label
            params={@params}
            payee_options={@payee_options}
            errors={errors(@errors, :payee_id)}
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.category_cell
              id="sched-category"
              prefix="sched"
              side={@main}
              label
              params={@params}
              accounts={@accounts}
              category_options={@category_options}
              errors={errors(@errors, :category_id)}
            />
            <.input
              id="sched-memo"
              name="transaction[memo]"
              value={@params["memo"]}
              label="Memo"
              placeholder="optional"
              autocomplete="off"
              phx-debounce="300"
              errors={errors(@errors, :memo)}
            />
          </div>
          <.parts
            :if={@params["split"] == "true"}
            prefix="sched"
            params={@params}
            accounts={@accounts}
            payee_options={@payee_options}
            category_options={@category_options}
            payee_shown={@payee_shown}
            target={@myself}
          />
          <hr class="my-3 border-base-content/10" />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              id="sched-date"
              type="date"
              name="transaction[date]"
              value={@params["date"]}
              label="Nächstes Datum"
              errors={errors(@errors, :next_date)}
            />
            <.input
              id="sched-repeat"
              type="select"
              name="transaction[repeat]"
              value={@params["repeat"]}
              options={@repeats}
              label="Wiederholen"
            />
          </div>
          <div :if={@params["repeat"] == "custom"} id="sched-every-row" class="flex items-start gap-2">
            <.input
              id="sched-every"
              type="number"
              name="transaction[every]"
              value={@params["every"]}
              label="Alle"
              min="1"
              max="99"
              class="w-20"
              errors={errors(@errors, :repeat_every)}
            />
            <div class="pt-7 max-sm:hidden">
              <.segmented
                id="sched-unit"
                mode={:radio}
                name="transaction[unit]"
                value={@params["unit"]}
                label="Wochen oder Monate"
                hide_label
                options={@units}
              />
            </div>
            <div class="pt-7 sm:hidden">
              <.input
                id="sched-unit-phone"
                type="select"
                name="transaction[unit_phone]"
                value={@params["unit"]}
                options={@units}
                label="Wochen oder Monate"
                hide_label
              />
            </div>
          </div>
          <p :if={@following != []} id="sched-following" class="text-sm text-base-content/70">
            Danach: {Enum.map_join(@following, " · ", &Format.date/1)}
          </p>
          <.option_lists
            prefix="sched"
            payee_options={@payee_options}
            category_options={@category_options}
          />
          <.alert :if={@error} id="sched-error" tone={:error} class="mt-3">{@error}</.alert>
          <.action_bar>
            <:secondary :if={@scheduled}>
              <.button
                id="sched-delete"
                variant={:ghost}
                class="text-error-ink"
                confirm="Geplante Buchung löschen?"
                phx-click="delete"
                phx-target={@myself}
              >
                Löschen …
              </.button>
            </:secondary>
            <.button id="sched-cancel" phx-click={hide_modal("scheduled-modal")}>Abbrechen</.button>
            <.button
              id="sched-save"
              type="submit"
              variant={:primary}
              phx-disable-with="Speichern …"
            >
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  defp errors(errors, field), do: Map.get(errors, field, [])

  defp kept_accounts(nil), do: []
  defp kept_accounts(scheduled), do: [scheduled.account_id]

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> EditorState.assign_accounts(assigns.scheduled, hide_shared_expenses: true)

    key = assigns.scheduled && assigns.scheduled.id

    if Map.get(socket.assigns, :loaded) == {key},
      do: {:ok, socket},
      else: {:ok, load(socket, key)}
  end

  defp load(socket, key) do
    socket
    |> EditorState.load(initial_params(socket.assigns))
    |> assign(loaded: {key}, errors: %{}, error: nil)
  end

  defp initial_params(%{scheduled: nil} = assigns) do
    assigns.account
    |> EditorFields.entry_account_id(assigns.accounts)
    |> TransactionForm.new(assigns.today)
    |> Map.merge(repeat_params(%ScheduledTransaction{repeat_unit: :month, repeat_every: 1}))
  end

  defp initial_params(%{scheduled: scheduled}),
    do: scheduled |> TransactionForm.from_scheduled() |> Map.merge(repeat_params(scheduled))

  defp repeat_params(%ScheduledTransaction{repeat_unit: unit, repeat_every: every}) do
    custom =
      if choice(unit, every) == "custom",
        do: %{"every" => to_string(every || 1), "unit" => to_string(unit)},
        else: %{"every" => "2", "unit" => "week"}

    Map.put(custom, "repeat", choice(unit, every))
  end

  defp choice(nil, _every), do: "once"
  defp choice(:month, every) when every in [nil, 1], do: "monthly"
  defp choice(:month, 12), do: "yearly"
  defp choice(_unit, _every), do: "custom"

  @impl true
  def handle_event("change", %{"transaction" => _changed} = event, socket) do
    socket =
      socket
      |> EditorState.change(phone_unit(event))
      |> assign(errors: %{}, error: nil)

    {:noreply, socket}
  end

  def handle_event("save", event, socket) do
    params = EditorState.submitted(socket, phone_unit(event))
    socket = assign(socket, :params, params)

    case save(socket.assigns, params) do
      {:ok, _scheduled} ->
        {:noreply, done(socket, "Geplante Buchung gespeichert.")}

      {:error, errors, error} ->
        {:noreply, assign(socket, errors: errors, error: error)}
    end
  end

  def handle_event("delete", _params, socket) do
    case Scheduled.delete(socket.assigns.current_scope, socket.assigns.scheduled) do
      {:ok, _deleted} -> {:noreply, done(socket, "Geplante Buchung gelöscht.")}
      {:error, :not_found} -> {:noreply, done(socket, "Die geplante Buchung ist schon gelöscht.")}
    end
  end

  def handle_event(event, params, socket),
    do: {:noreply, EditorState.handle_event(event, params, socket)}

  # The phone's select stands for the segmented control, so whichever changed last counts.
  defp phone_unit(%{"_target" => ["transaction", "unit_phone"]} = event),
    do: update_in(event, ["transaction"], &Map.put(&1, "unit", &1["unit_phone"]))

  defp phone_unit(event), do: event

  defp save(assigns, params) do
    %{accounts: accounts, scheduled: scheduled, current_scope: scope} = assigns

    with :ok <- check(params, assigns),
         {:ok, attrs} <- to_attrs(params, accounts, scheduled) do
      case write(scope, scheduled, attrs) do
        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, field_errors(changeset), rest(changeset)}

        {:error, :not_found} ->
          {:error, %{}, "Die geplante Buchung ist gelöscht."}

        {:ok, saved} ->
          {:ok, saved}
      end
    end
  end

  defp write(scope, nil, attrs), do: Scheduled.create(scope, attrs)
  defp write(scope, scheduled, attrs), do: Scheduled.update(scope, scheduled, attrs)

  defp to_attrs(params, accounts, scheduled) do
    case TransactionForm.to_attrs(params, accounts, scheduled) do
      {:ok, attrs} ->
        {:ok,
         attrs
         |> Map.drop([:date, :approved])
         |> Map.merge(%{next_date: attrs.date} |> Map.merge(repeat(params)))}

      {:error, message} ->
        {:error, %{}, message}
    end
  end

  defp repeat(%{"repeat" => "once"}), do: %{repeat_unit: nil, repeat_every: nil}
  defp repeat(%{"repeat" => "yearly"}), do: %{repeat_unit: :month, repeat_every: 12}
  defp repeat(%{"repeat" => "custom"} = params), do: custom(params) || %{}
  defp repeat(_monthly), do: %{repeat_unit: :month, repeat_every: 1}

  defp custom(params) do
    with {every, ""} when every in 1..99 <- Integer.parse(params["every"] || ""),
         unit when unit in ["week", "month"] <- params["unit"] do
      %{repeat_unit: String.to_existing_atom(unit), repeat_every: every}
    else
      _invalid -> nil
    end
  end

  # What the form reads itself, so that each error stands at its field before the Ledger checks the rest.
  defp check(params, assigns) do
    errors =
      %{}
      |> put_error(:account_id, account_error(params, assigns))
      |> put_error(:amount, amount_error(params))
      |> put_error(:next_date, date_error(params["date"]))
      |> put_error(:repeat_every, every_error(params))

    if errors == %{}, do: :ok, else: {:error, errors, nil}
  end

  defp put_error(errors, _field, nil), do: errors
  defp put_error(errors, field, message), do: Map.put(errors, field, [message])

  defp account_error(params, assigns) do
    id = TransactionForm.to_id(params["account_id"])
    account = id && Map.get(assigns.accounts, id)

    if account && EditorFields.offered_account?(account, kept_accounts(assigns.scheduled)),
      do: nil,
      else: "muss ausgewählt werden"
  end

  defp amount_error(params) do
    case TransactionForm.amount(params) do
      {:ok, _cents} -> nil
      {:error, message} -> message
    end
  end

  defp date_error(text) do
    cond do
      String.trim(text || "") == "" -> "muss ausgefüllt werden"
      match?({:ok, _date}, Date.from_iso8601(text)) -> nil
      true -> "ist kein gültiges Datum"
    end
  end

  defp every_error(%{"repeat" => "custom"} = params),
    do: if(custom(params), do: nil, else: "muss eine Zahl von 1 bis 99 sein")

  defp every_error(_params), do: nil

  defp field_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Map.take(@fields)
  end

  defp rest(changeset) do
    case Map.drop(changeset |> Ecto.Changeset.traverse_errors(&translate_error/1), @fields) do
      empty when empty == %{} ->
        nil

      _rest ->
        changeset
        |> Map.update!(:errors, &Keyword.drop(&1, @fields))
        |> TransactionEditor.error_message()
    end
  end

  defp following(params) do
    with {:ok, date} <- Date.from_iso8601(params["date"] || ""),
         %{repeat_unit: unit, repeat_every: every} <- repeat(params) do
      ScheduledTransaction.dates_after(
        %ScheduledTransaction{next_date: date, repeat_unit: unit, repeat_every: every},
        3
      )
    else
      _unreadable -> []
    end
  end

  defp done(socket, message) do
    send(self(), {__MODULE__, :done, message})
    socket
  end
end
