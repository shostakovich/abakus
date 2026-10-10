defmodule AbakusWeb.BudgetLive.TargetForm do
  @moduledoc """
  The target editor in the inspector's target card, as in YNAB: the amount, monthly or by a date (with the date and
  "Jährlich wiederholen"), "Weitere zurücklegen" or "Auffüllen bis"; save, delete and cancel. The form holds what
  was typed; saving sets the target from the focus month on (`Abakus.Categories.set_target/2`).
  """
  use AbakusWeb, :html

  alias Abakus.Categories.TargetVersion
  alias AbakusWeb.Format

  @blank %{
    "amount" => "",
    "cadence" => "monthly",
    "due_on" => "",
    "repeats_yearly" => "false",
    "set_aside" => "true"
  }

  @doc """
  The editor's fields for a target, or for a new one, to save from `month` on; a repeating target's date moves on
  to its next due date.
  """
  def params(nil, _month), do: @blank

  def params(target, month) do
    %{
      "amount" => Format.amount(target.amount),
      "cadence" => Atom.to_string(target.cadence),
      "due_on" => due_on(target, month),
      "repeats_yearly" => to_string(target.repeats_yearly),
      "set_aside" => to_string(target.set_aside)
    }
  end

  defp due_on(%{due_on: nil}, _month), do: ""

  defp due_on(%{due_on: due_on, repeats_yearly: true}, month),
    do: due_on |> TargetVersion.next_due(month) |> Date.to_iso8601()

  defp due_on(%{due_on: due_on}, _month), do: Date.to_iso8601(due_on)

  def to_target_form(params, errors \\ []),
    do: to_form(Map.merge(@blank, params), as: :target, errors: errors)

  @doc """
  The target version's attrs from the fields, from `month` on; a monthly target drops the date and the repeat.
  An amount that is no number is `{:error, errors}` on the amount.
  """
  def attrs(params, month) do
    params = Map.merge(@blank, params)
    by_date = params["cadence"] == "by_date"

    case amount(params["amount"]) do
      {:ok, amount} ->
        {:ok,
         %{
           from_month: month,
           cadence: params["cadence"],
           amount: amount,
           due_on: if(by_date, do: blank_to_nil(params["due_on"])),
           repeats_yearly: by_date and params["repeats_yearly"] == "true",
           set_aside: params["set_aside"] != "false"
         }}

      :error ->
        {:error, [amount: {"Betrag ist ungültig, etwa 1.234,56", []}]}
    end
  end

  defp amount(text) when is_binary(text) do
    if String.trim(text) == "", do: :error, else: Format.parse_amount(text)
  end

  defp amount(_text), do: :error

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  attr :form, Phoenix.HTML.Form, required: true
  attr :target, :any, required: true, doc: "the target in effect, nil for a new one"

  @doc "The editor."
  def editor(assigns) do
    assigns = assign(assigns, :by_date, assigns.form[:cadence].value == "by_date")

    ~H"""
    <.form
      for={@form}
      id="target-form"
      class="d-flex flex-column gap-2"
      phx-change="target_change"
      phx-submit="save_target"
    >
      <div class="fw-semibold">Für Ausgaben benötigt</div>
      <div>
        <label class="form-label mb-1" for="target-amount">Ich brauche</label>
        <div class="input-group input-group-sm has-validation">
          <input
            id="target-amount"
            name={@form[:amount].name}
            value={@form[:amount].value}
            class={["form-control text-end app-q", @form[:amount].errors != [] && "is-invalid"]}
            inputmode="decimal"
            autocomplete="off"
            required
            phx-mounted={JS.focus()}
          />
          <span class="input-group-text">€</span>
        </div>
        <.field_errors field={@form[:amount]} />
      </div>
      <div class="btn-group btn-group-sm w-100" role="group" aria-label="Rhythmus">
        <%= for {value, label} <- [{"monthly", "Jeden Monat"}, {"by_date", "Bis zum Datum"}] do %>
          <input
            type="radio"
            class="btn-check"
            name={@form[:cadence].name}
            id={"target-cadence-#{value}"}
            value={value}
            checked={@form[:cadence].value == value}
          />
          <label class="btn btn-outline-secondary" for={"target-cadence-#{value}"}>{label}</label>
        <% end %>
      </div>
      <div :if={@by_date} id="target-due">
        <label class="form-label mb-1" for="target-due-on">Fällig am</label>
        <input
          type="date"
          id="target-due-on"
          name={@form[:due_on].name}
          value={@form[:due_on].value}
          class={["form-control form-control-sm", @form[:due_on].errors != [] && "is-invalid"]}
          required
        />
        <.field_errors field={@form[:due_on]} />
        <.input
          field={@form[:repeats_yearly]}
          id="target-repeats"
          type="checkbox"
          switch
          label="Jährlich wiederholen"
          wrapper_class="mt-2 mb-0"
        />
      </div>
      <div>
        <label class="form-label mb-1" for="target-set-aside">Nächsten Monat möchte ich:</label>
        <select id="target-set-aside" name={@form[:set_aside].name} class="form-select form-select-sm">
          {Phoenix.HTML.Form.options_for_select(
            [{"Weitere zurücklegen", "true"}, {"Auffüllen bis", "false"}],
            @form[:set_aside].value
          )}
        </select>
      </div>
      <.field_errors field={@form[:cadence]} />
      <div class="d-flex gap-2 mt-1">
        <button id="target-save" type="submit" class="btn btn-sm btn-primary flex-grow-1">
          Speichern
        </button>
        <button
          id="target-cancel"
          type="button"
          class="btn btn-sm btn-light"
          phx-click="cancel_target"
        >
          Abbrechen
        </button>
      </div>
      <button
        :if={@target}
        id="target-delete"
        type="button"
        class="btn btn-sm btn-link text-danger px-0 align-self-start"
        phx-click="delete_target"
        data-confirm="Ziel löschen? Die Kategorie hat ab diesem Monat kein Ziel mehr."
      >
        Ziel löschen
      </button>
    </.form>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    ~H"""
    <.error :for={error <- @field.errors}>{translate_error(error)}</.error>
    """
  end
end
