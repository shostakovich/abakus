defmodule AbakusWeb.Kasse.ExpenseLive do
  @moduledoc """
  The form of an expense or reimbursement: new (`:new`, prefilled for a suggested reimbursement)
  or saved (`:edit`, read-only once deleted, with its history and, for the budget owner, the
  transaction it is linked to in the budget). Every change goes through
  `Abakus.Kasse.Expenses.Form`, which keeps the text as typed and fills in what an edit implies;
  the split shows live, and a foreign rate is looked up as currency or date change.

  Errors of a submit stay on the fields until they change.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Kasse.{Activities, BudgetLink, Categories, Expenses, Participants, Split}
  alias Abakus.Kasse.Expenses.{Expense, Form}
  alias Abakus.LocalTime
  alias Ecto.Changeset
  alias Phoenix.HTML.FormData

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        suggestions: Expenses.category_suggestions(socket.assigns.current_scope),
        people: Participants.list_participants(socket.assigns.current_scope, :all),
        categories: Categories.list_categories(socket.assigns.current_scope, :all),
        errors: [],
        submitted: nil
      )

    {:ok, socket |> start(socket.assigns.live_action, params) |> assign_form()}
  end

  defp amount_cents(text) when is_binary(text) do
    case Integer.parse(text) do
      {cents, ""} when cents > 0 -> cents
      _invalid -> nil
    end
  end

  defp amount_cents(_none), do: nil

  defp start(socket, :new, params) do
    known = MapSet.new(socket.assigns.people, & &1.id)

    person = fn key ->
      with {:ok, id} <- Abakus.Schema.cast_id(params[key]),
           true <- id in known,
           do: id,
           else: (_none -> nil)
    end

    data =
      Expenses.new_form(socket.assigns.current_scope,
        today: LocalTime.today(),
        reimbursement: params["reimbursement"] in ["1", "true"],
        from: person.("from"),
        to: person.("to"),
        amount_cents: amount_cents(params["amount"])
      )

    assign(socket,
      page_title: "Neue Ausgabe",
      expense: nil,
      deleted?: false,
      data: data,
      history: [],
      booking: nil
    )
  end

  defp start(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope

    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %Expense{} = expense <- Expenses.get_expense(scope, id) do
      assign(socket,
        page_title: expense.title,
        expense: expense,
        deleted?: Expense.deleted?(expense),
        data: Expenses.edit_form(scope, expense),
        history: Activities.list_activities(scope, expense_id: expense.id),
        booking: BudgetLink.transaction_for(scope, expense.id)
      )
    else
      _missing -> raise AbakusWeb.NotFoundError
    end
  end

  @impl true
  def handle_event("change", %{"expense" => params}, socket) do
    changeset = changeset(socket, params)

    {:noreply,
     socket
     |> assign(data: Changeset.apply_changes(changeset))
     |> keep_errors()
     |> then(&if(Form.rate_lookup?(changeset), do: lookup_rate(&1), else: &1))
     |> assign_form()}
  end

  def handle_event("recover", %{"expense" => params}, socket) do
    data = socket.assigns.data |> Form.restore(params) |> Changeset.apply_changes()
    {:noreply, socket |> assign(data: data) |> assign_form()}
  end

  def handle_event("select_all", _params, socket) do
    data = socket.assigns.data |> Form.select_all() |> Changeset.apply_changes()
    {:noreply, socket |> assign(data: data) |> keep_errors() |> assign_form()}
  end

  def handle_event("load_rate", _params, socket),
    do: {:noreply, socket |> lookup_rate() |> assign_form()}

  def handle_event("save", %{"expense" => params}, socket) do
    data = socket |> changeset(params) |> Changeset.apply_changes()
    %{current_scope: scope, expense: expense} = socket.assigns

    case Expenses.save_form(scope, data, expense) do
      {:ok, saved} ->
        kind = if saved.reimbursement, do: "Rückzahlung", else: "Ausgabe"
        verb = if expense, do: "gespeichert", else: "angelegt"

        {:noreply,
         socket
         |> put_flash(:info, "#{kind} „#{saved.title}“ #{verb}.")
         |> push_navigate(to: ~p"/kasse")}

      {:error, %Changeset{} = changeset} ->
        data = Changeset.apply_changes(changeset)

        {:noreply,
         socket
         |> assign(data: data, errors: changeset.errors, submitted: data)
         |> assign_form()}

      {:error, :deleted} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Diese Ausgabe wurde gelöscht und kann nicht mehr bearbeitet werden."
         )
         |> push_navigate(to: ~p"/kasse/expenses/#{expense}")}

      {:error, :not_found} ->
        {:noreply,
         socket |> put_flash(:error, "Ausgabe nicht gefunden.") |> push_navigate(to: ~p"/kasse")}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_scope: scope, expense: expense} = socket.assigns

    case Expenses.delete_expense(scope, expense) do
      {:ok, deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{deleted.title}“ gelöscht.")
         |> push_navigate(to: ~p"/kasse")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Ausgabe nicht gefunden oder schon gelöscht.")
         |> push_navigate(to: ~p"/kasse")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, error_text(changeset))}
    end
  end

  defp changeset(socket, params),
    do: Form.changeset(socket.assigns.data, params, suggestions: socket.assigns.suggestions)

  defp lookup_rate(socket) do
    %{current_scope: scope, data: data} = socket.assigns
    data = scope |> Expenses.lookup_form_rate(data) |> Changeset.apply_changes()
    assign(socket, data: data)
  end

  defp keep_errors(%{assigns: %{errors: []}} = socket), do: socket

  defp keep_errors(socket) do
    %{errors: errors, submitted: submitted, data: data} = socket.assigns

    assign(socket,
      errors:
        Enum.filter(errors, fn {field, _} -> watched(submitted, field) == watched(data, field) end)
    )
  end

  defp watched(form, :currency), do: Form.currency_code(form)
  defp watched(form, :amount), do: {form.amount, Form.currency_code(form)}

  defp watched(form, :rows),
    do: {form.rows, form.split_mode, form.reimbursement, form.amount, Form.currency_code(form)}

  defp watched(form, field), do: Map.get(form, field)

  defp assign_form(socket) do
    %{data: data, errors: errors} = socket.assigns

    changeset = %{
      Changeset.change(data)
      | params: params(data),
        errors: errors,
        action: if(errors != [], do: :validate)
    }

    form = to_form(changeset, as: :expense)
    code = Form.currency_code(data)
    unit = if code in ["", "EUR"], do: "€", else: code

    assign(socket,
      form: form,
      rows: FormData.to_form(changeset, form, :rows, []),
      preview: Expenses.preview_form(socket.assigns.current_scope, data),
      foreign?: code not in ["", "EUR"],
      unit: unit,
      unit_label: unit_label(data, unit),
      weights?: not data.reimbursement and data.split_mode != :equal,
      all_selected?: Enum.all?(data.rows, & &1.selected)
    )
  end

  # The form's values as params, so that errors count as entered and every field shows `data`.
  defp params(data) do
    fields =
      ~w(title date category_id paid_by_id currency currency_other amount rate notes reimbursement split_mode)a

    rows =
      for {row, index} <- Enum.with_index(data.rows), into: %{} do
        {"#{index}",
         %{
           "participant_id" => row.participant_id,
           "selected" => row.selected,
           "weight" => row.weight
         }}
      end

    fields |> Map.new(&{Atom.to_string(&1), Map.fetch!(data, &1)}) |> Map.put("rows", rows)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.kasse
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:expenses}
      fab={false}
    >
      <.header back={~p"/kasse"} back_label="Ausgaben">
        {heading(@expense, @deleted?)}
        <:subtitle :if={@expense}>{created(@expense)}</:subtitle>
        <:badge :if={@expense && @expense.recurring_expense_id}>
          <.badge icon="repeat">Wiederkehrend</.badge>
        </:badge>
      </.header>

      <.alert :if={@deleted?} tone={:warning} class="mb-6">
        Diese Ausgabe wurde am {Format.datetime(@expense.deleted_at)} gelöscht
        und zählt nicht mehr zu den Salden.
      </.alert>

      <.form
        for={@form}
        id="expense-form"
        phx-change="change"
        phx-submit="save"
        phx-auto-recover="recover"
        phx-hook="Setzkasten.Components.Forms.FocusInvalid"
        novalidate
      >
        <.alert :if={@errors != []} tone={:error} title={error_title(@errors)} class="mb-4">
          Bitte prüfe die markierten Felder.
        </.alert>
        <fieldset disabled={@deleted?} class="min-w-0">
          <div class="grid gap-x-4 md:grid-cols-2">
            <.input
              field={@form[:title]}
              label="Titel"
              required
              maxlength="200"
              placeholder="z. B. Einkauf Wochenmarkt"
              autocomplete="off"
              enterkeyhint="next"
            />
            <.input field={@form[:date]} type="date" label="Datum" required />
            <.input
              field={@form[:category_id]}
              type="select"
              label="Kategorie"
              prompt="Keine Kategorie"
              options={category_options(@categories, @data.category_id)}
              help={@data.category_suggested && "Vorschlag anhand früherer Ausgaben"}
            />
            <.input
              field={@form[:paid_by_id]}
              type="select"
              label={if @data.reimbursement, do: "Zurückgezahlt von", else: "Bezahlt von"}
              options={payer_options(@people, @data.paid_by_id)}
              required
            />
            <div>
              <.input
                field={@form[:currency]}
                type="select"
                label="Währung"
                options={currency_options()}
              />
              <.input
                :if={@data.currency == ""}
                field={@form[:currency_other]}
                label="Andere Währung (ISO-Code)"
                hide_label
                maxlength="3"
                placeholder="ISO-Code, z. B. THB"
                autocapitalize="characters"
                autocomplete="off"
                class="mt-2"
              />
            </div>
            <.input
              field={@form[:amount]}
              label="Betrag"
              suffix={@unit}
              numeric
              required
              placeholder="0,00"
              autocomplete="off"
            />
            <%= if @foreign? do %>
              <div>
                <input type="hidden" name={@form[:rate_source].name} value={@data.rate_source} />
                <.input
                  field={@form[:rate]}
                  label="Wechselkurs"
                  prefix="1 € ="
                  suffix={@unit}
                  numeric
                  placeholder="automatisch"
                  autocomplete="off"
                  help={rate_hint(@data)}
                />
                <.button
                  :if={@data.rate_source != :ecb}
                  id="expense-load-rate"
                  variant={:ghost}
                  size={:sm}
                  icon="refresh-cw"
                  phx-click="load_rate"
                  class="-ms-3"
                >
                  EZB-Kurs laden
                </.button>
              </div>
              <.description_list class="pt-2 md:pt-9">
                <:item label="Umgerechnet in Euro">
                  <span id="expense-eur" class="font-semibold">
                    <.amount :if={@preview.eur_cents} value={@preview.eur_cents} />
                    <span :if={!@preview.eur_cents}>–</span>
                  </span>
                </:item>
              </.description_list>
            <% end %>
            <div class="md:col-span-2">
              <.input
                field={@form[:reimbursement]}
                type="checkbox"
                label="Das ist eine Rückzahlung"
              />
            </div>
            <div class="md:col-span-2">
              <.input
                field={@form[:notes]}
                type="textarea"
                label="Notiz"
                rows="2"
                maxlength="2000"
              />
            </div>
          </div>

          <fieldset
            id="expense-split"
            class="mt-8 min-w-0"
            aria-labelledby="expense-split-heading"
            aria-describedby={split_describedby(@form)}
            aria-invalid={@form[:rows].errors != [] && "true"}
          >
            <.section_heading id="expense-split-heading">
              {if @data.reimbursement, do: "An wen?", else: "Für wen?"}
              <:actions :if={!@data.reimbursement}>
                <.button id="expense-select-all" variant={:ghost} size={:sm} phx-click="select_all">
                  {if @all_selected?, do: "Keine auswählen", else: "Alle auswählen"}
                </.button>
              </:actions>
            </.section_heading>
            <p class="mb-3 text-sm text-base-content/70">
              {if @data.reimbursement,
                do: "Wähle genau eine Person, die das Geld bekommen hat.",
                else: "Wähle, für wen bezahlt wurde."}
            </p>
            <.table
              id="expense-rows"
              rows={@rows}
              row_id={&"split-row-#{&1[:participant_id].value}"}
              size={:dense}
            >
              <:col :let={row} label="Person">
                <input
                  type="hidden"
                  name={row[:participant_id].name}
                  value={row[:participant_id].value}
                />
                <.input
                  field={row[:selected]}
                  type="checkbox"
                  bare
                  label={archived_label(row[:name].value, row[:archived].value)}
                />
              </:col>
              <:col :let={row} :if={@weights?} label={@unit_label} align={:end}>
                <.input
                  field={row[:weight]}
                  label={"Wert für #{row[:name].value}"}
                  hide_label
                  numeric
                  autocomplete="off"
                  class="ms-auto w-28"
                />
              </:col>
              <:col :let={row} label="Anteil" align={:end}>
                <.amount
                  :if={cents = row[:selected].value && @preview.shares[row[:participant_id].value]}
                  value={cents}
                  class="text-base-content/70"
                />
              </:col>
            </.table>
            <.field_error id="expense-rows" field={@form[:rows]} />
            <p
              :if={!@data.reimbursement}
              id="expense-split-sum"
              class={["mt-3 text-sm", sum_tone(@preview.sum)]}
              aria-live="polite"
            >
              {sum_text(@preview.sum)}
            </p>
            <.disclosure
              :if={!@data.reimbursement}
              id="expense-split-more"
              variant={:button}
              summary="Weitere Aufteilungsoptionen …"
              open={@data.split_mode != :equal}
              class="mt-4"
            >
              <.input
                field={@form[:split_mode]}
                type="select"
                label="Aufteilung"
                options={Enum.map(Split.modes(), &{Split.label(&1), &1})}
                help={split_help(@unit)}
              />
            </.disclosure>
          </fieldset>
        </fieldset>

        <.action_bar :if={!@deleted?} sticky>
          <:secondary :if={@expense}>
            <.button
              id="expense-delete"
              variant={:danger_outline}
              icon="trash-2"
              confirm="Diese Ausgabe wirklich löschen?"
              confirm_text="Sie verschwindet aus Liste und Salden; im Aktivitätsprotokoll bleibt sie sichtbar."
              phx-click="delete"
            >
              Löschen
            </.button>
          </:secondary>
          <.button navigate={~p"/kasse"}>Abbrechen</.button>
          <.button
            id="expense-submit"
            type="submit"
            variant={:primary}
            icon="save"
            phx-disable-with="Speichert …"
          >
            {if @expense, do: "Speichern", else: "Anlegen"}
          </.button>
        </.action_bar>
      </.form>

      <section :if={@booking} aria-labelledby="expense-budget" class="mt-8">
        <.section_heading id="expense-budget">Im Budget</.section_heading>
        <.description_list id="expense-budget-facts">
          <:item label="Dein Anteil"><.amount value={-@booking.amount} /></:item>
          <:item label="Kategorie">
            {if @booking.category, do: @booking.category.name, else: "Nicht kategorisiert"}
          </:item>
        </.description_list>
        <.button
          id="expense-register"
          navigate={~p"/budget/accounts/#{@booking.account_id}"}
          variant={:ghost}
          size={:sm}
          icon="wallet"
          class="-ms-3 mt-2"
        >
          Im Register ansehen
        </.button>
      </section>

      <section :if={@expense} aria-labelledby="expense-history" class="mt-8">
        <.section_heading id="expense-history">Verlauf</.section_heading>
        <p :if={!@deleted? && @expense.recurring_expense_id} class="mb-2 text-sm">
          Diese Ausgabe wird automatisch wiederholt.
          <.link href={~p"/settings/kasse/recurring"} class="link link-primary">
            Wiederkehrende Ausgaben verwalten
          </.link>
        </p>
        <div :if={!@deleted? && !@expense.recurring_expense_id} class="mb-2">
          <.button
            href={~p"/settings/kasse/recurring/new?#{[expense_id: @expense.id]}"}
            variant={:ghost}
            size={:sm}
            icon="repeat"
            class="-ms-3"
          >
            Als wiederkehrend einrichten
          </.button>
        </div>
        <.list :if={@history != []} id="expense-activities">
          <.activity_entry
            :for={activity <- @history}
            id={"activity-#{activity.id}"}
            activity={activity}
          />
        </.list>
        <.empty_state :if={@history == []} title="Noch keine Einträge." />
      </section>
    </Layouts.kasse>
    """
  end

  defp heading(nil, _deleted?), do: "Ausgabe hinzufügen"
  defp heading(_expense, true), do: "Gelöschte Ausgabe"
  defp heading(_expense, false), do: "Ausgabe bearbeiten"

  defp created(expense) do
    created = "Angelegt am " <> Format.datetime(expense.inserted_at)

    if expense.updated_at == expense.inserted_at,
      do: created,
      else: join_meta([created, "geändert am " <> Format.datetime(expense.updated_at)])
  end

  defp error_text(changeset),
    do: Enum.map_join(changeset.errors, " ", fn {_field, {message, _opts}} -> message end)

  defp error_title([_one]), do: "1 Feld ist noch nicht richtig"
  defp error_title(errors), do: "#{length(errors)} Felder sind noch nicht richtig"

  defp category_options(categories, current) do
    for category <- categories, is_nil(category.archived_at) or category.id == current do
      {archived_label(category.name, not is_nil(category.archived_at)), category.id}
    end
  end

  defp payer_options(people, current) do
    for person <- people, is_nil(person.archived_at) or person.id == current do
      {archived_label(person.name, not is_nil(person.archived_at)), person.id}
    end
  end

  defp archived_label(name, true), do: "#{name} (archiviert)"
  defp archived_label(name, _active), do: name

  defp currency_options do
    common = for code <- Form.common_currencies(), do: {currency_label(code), code}
    common ++ [{"Andere …", ""}]
  end

  defp currency_label("EUR"), do: "EUR – Euro"
  defp currency_label(code), do: code

  defp rate_hint(%Form{rate_hint: hint}) when is_binary(hint), do: hint
  defp rate_hint(%Form{rate_source: :manual}), do: "Von Hand eingetragener Kurs."
  defp rate_hint(%Form{rate_source: :ecb}), do: "EZB-Kurs."
  defp rate_hint(_data), do: "Leer lassen für den EZB-Kurs."

  defp sum_text({_ok_or_error, text}), do: text
  defp sum_text(nil), do: nil

  defp sum_tone({:error, _text}), do: "text-error-ink"
  defp sum_tone(_sum), do: nil

  defp split_describedby(form) do
    if form[:rows].errors != [] and Phoenix.Component.used_input?(form[:rows]),
      do: "expense-rows-error-0"
  end

  defp split_help("€"),
    do:
      "Nach Anteilen: z. B. 2 : 1. Nach Prozent: zusammen 100 %. Nach Beträgen: zusammen der Gesamtbetrag."

  defp split_help(code),
    do:
      "Nach Anteilen: z. B. 2 : 1. Nach Prozent: zusammen 100 %. Nach Beträgen: zusammen der Gesamtbetrag in #{code}."

  defp unit_label(%Form{split_mode: :shares}, _unit), do: "Anteile"
  defp unit_label(%Form{split_mode: :percent}, _unit), do: "%"
  defp unit_label(_data, unit), do: unit
end
