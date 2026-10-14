defmodule AbakusWeb.BudgetLive.TargetForm do
  @moduledoc """
  The target editor in a category's dialog (its sheet on phones), as in YNAB: the amount, monthly or by a date (with the date and
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

    case parse_target_amount(params["amount"]) do
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

  defp parse_target_amount(text) when is_binary(text) do
    if String.trim(text) == "", do: :error, else: Format.parse_amount(text)
  end

  defp parse_target_amount(_text), do: :error

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  attr :form, Phoenix.HTML.Form, required: true
  attr :target, :any, required: true, doc: "the target in effect, nil for a new one"

  @doc "The editor."
  def editor(assigns) do
    assigns = assign(assigns, :by_date, assigns.form[:cadence].value == "by_date")

    ~H"""
    <.form for={@form} id="target-form" phx-change="target_change" phx-submit="save_target">
      <p class="text-sm font-medium">Für Ausgaben benötigt</p>
      <.input
        field={@form[:amount]}
        id="target-amount"
        label="Ich brauche"
        suffix="€"
        numeric
        autocomplete="off"
        required
        phx-mounted={JS.focus()}
      />
      <.segmented
        id="target-cadence"
        mode={:radio}
        field={@form[:cadence]}
        label="Rhythmus"
        size={:sm}
        block
        class="mt-2"
        options={[{"Jeden Monat", "monthly"}, {"Bis zum Datum", "by_date"}]}
      />
      <div :if={@by_date} id="target-due">
        <.input field={@form[:due_on]} id="target-due-on" type="date" label="Fällig am" required />
        <.input
          field={@form[:repeats_yearly]}
          id="target-repeats"
          type="toggle"
          label="Jährlich wiederholen"
        />
      </div>
      <.input
        field={@form[:set_aside]}
        id="target-set-aside"
        type="select"
        label="Nächsten Monat möchte ich:"
        options={[{"Weitere zurücklegen", "true"}, {"Auffüllen bis", "false"}]}
      />
      <fieldset :if={@form[:cadence].errors != []} class="fieldset">
        <.field_error id="target-cadence" errors={@form[:cadence].errors} />
      </fieldset>
      <div class="mt-3 flex flex-wrap justify-between gap-2">
        <div class="flex gap-2">
          <.button id="target-save" type="submit" variant={:primary} size={:sm}>Speichern</.button>
          <.button id="target-cancel" size={:sm} phx-click="cancel_target">Abbrechen</.button>
        </div>
        <.button
          :if={@target}
          id="target-delete"
          variant={:danger_outline}
          size={:sm}
          confirm="Ziel löschen?"
          confirm_text="Die Kategorie hat ab diesem Monat kein Ziel mehr."
          phx-click="delete_target"
        >
          Ziel löschen
        </.button>
      </div>
    </.form>
    """
  end
end
