defmodule AbakusWeb.Bookkeeping.TaxLineDialog do
  @moduledoc """
  The dialog „Buchhaltung“ for one transaction: a Kategorie and its Umsatzsteuer per side (the transaction, or each
  part of a split), with the net and VAT amount they make; choosing a category sets its usual VAT treatment, and
  „Keine“ removes the side's tax line. With `next` the button reads „Speichern und weiter“. Tells its LiveView
  `{TaxLineDialog, :done, transaction_id}` once saved, or once the transaction is gone; `close_tax_lines` goes to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Bookkeeping, Format, Money}
  alias Abakus.Bookkeeping.{Category, Vat}

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :shown, Enum.map(assigns.sides, &with_amounts(&1, assigns)))

    ~H"""
    <div id={@id}>
      <.modal
        id="tax-lines-modal"
        show
        title="Buchhaltung"
        placement={:top}
        on_cancel={JS.push("close_tax_lines")}
      >
        <p id="tax-lines-transaction" class="mb-3 text-sm text-base-content/70">
          {join_meta([
            Format.date(@transaction.date),
            payee_name(@transaction),
            Money.euros(@transaction.amount, signed: true)
          ])}
        </p>
        <.form
          for={%{}}
          id="tax-lines-form"
          class="flex flex-col gap-4"
          phx-change="change"
          phx-submit="save"
          phx-target={@myself}
        >
          <fieldset :for={side <- @shown} id={"tax-side-#{side.key}"} class="flex flex-col">
            <legend :if={side.part} class="text-sm font-medium">
              {join_meta([
                part_name(side.part, @transaction),
                Money.euros(side.part.amount, signed: true)
              ])}
            </legend>
            <div class="grid gap-x-4 sm:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
              <.input
                id={"tax-#{side.key}-category"}
                type="select"
                name={"sides[#{side.key}][category]"}
                value={@params[side.key]["category"]}
                options={category_options()}
                prompt="Keine"
                label="Kategorie"
                errors={errors(@errors, side.key, :category)}
              />
              <.input
                id={"tax-#{side.key}-vat"}
                type="select"
                name={"sides[#{side.key}][vat]"}
                value={@params[side.key]["vat"]}
                options={vat_options()}
                label="Umsatzsteuer"
                errors={errors(@errors, side.key, :vat)}
              />
            </div>
            <p :if={side.amounts} id={"tax-#{side.key}-amounts"} class="text-sm text-base-content/70">
              Netto {Money.euros(side.amounts.net, signed: true)} · USt {Money.euros(
                side.amounts.vat,
                signed: true
              )}
            </p>
          </fieldset>
          <.action_bar>
            <.button id="tax-lines-cancel" phx-click={hide_modal("tax-lines-modal")}>
              Abbrechen
            </.button>
            <.button
              id="tax-lines-save"
              type="submit"
              variant={:primary}
              phx-disable-with="Speichern …"
            >
              {if @next, do: "Speichern und weiter", else: "Speichern"}
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  @doc "The categories for a select, in their Lexoffice groups."
  def category_options do
    for {group, categories} <- Category.grouped(),
        do: {group, Enum.map(categories, &{&1.name, &1.key})}
  end

  defp vat_options, do: Enum.map(Vat.treatments(), &{Vat.label(&1), stored(&1)})

  defp stored(treatment), do: Keyword.fetch!(Vat.stored(), treatment)

  defp treatment(value), do: Enum.find(Vat.treatments(), &(stored(&1) == value))

  defp with_amounts(side, assigns),
    do:
      Map.put(
        side,
        :amounts,
        amounts(assigns.params[side.key], side.amount, assigns.transaction.date)
      )

  defp amounts(%{"category" => key, "vat" => vat}, amount, date) do
    with %Category{} <- Category.get(key),
         treatment when not is_nil(treatment) <- treatment(vat) do
      Vat.amounts(amount, treatment, date)
    else
      _none -> nil
    end
  end

  defp amounts(_params, _amount, _date), do: nil

  defp errors(errors, key, field) do
    case errors[key] do
      nil -> []
      changeset -> Keyword.get_values(changeset.errors, field)
    end
  end

  defp payee_name(%{payee: %{name: name}}), do: name
  defp payee_name(_transaction), do: "Ohne Empfänger"

  defp part_name(%{payee: %{name: name}}, _transaction), do: name
  defp part_name(%{memo: memo}, _transaction) when memo not in [nil, ""], do: memo
  defp part_name(_part, transaction), do: payee_name(transaction)

  @impl true
  def update(%{transaction: transaction} = assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :current_scope, :next]))

    if socket.assigns[:transaction] && socket.assigns.transaction.id == transaction.id do
      {:ok, assign(socket, :transaction, transaction)}
    else
      {:ok, load(socket, transaction)}
    end
  end

  defp load(socket, transaction) do
    lines = Bookkeeping.tax_lines(socket.assigns.current_scope, [transaction])
    parts = Map.new(transaction.subtransactions, &{&1.id, &1})

    sides =
      for side <- Bookkeeping.sides(transaction) do
        part = side && parts[side]
        %{key: Bookkeeping.side_key(side), part: part, amount: (part || transaction).amount}
      end

    params =
      Map.new(Bookkeeping.sides(transaction), fn side ->
        line = lines[{transaction.id, side}]

        {Bookkeeping.side_key(side),
         %{"category" => line && line.category, "vat" => line && stored(line.vat)}}
      end)

    assign(socket, transaction: transaction, sides: sides, params: params, errors: %{})
  end

  @impl true
  def handle_event("change", %{"sides" => sides}, socket) do
    params =
      Map.new(socket.assigns.params, fn {key, old} ->
        {key, follow_category(old, Map.get(sides, key, old))}
      end)

    {:noreply, assign(socket, :params, params)}
  end

  def handle_event("save", %{"sides" => sides}, socket) do
    %{current_scope: scope, transaction: transaction} = socket.assigns

    case Bookkeeping.save_tax_lines(scope, transaction, sides) do
      {:error, %{} = errors} ->
        {:noreply, assign(socket, params: sides, errors: errors)}

      _saved_or_gone ->
        send(self(), {__MODULE__, :done, transaction.id})
        {:noreply, socket}
    end
  end

  defp follow_category(%{"category" => key}, %{"category" => key} = new), do: new

  defp follow_category(_old, %{"category" => key} = new) do
    case Category.get(key) do
      nil -> new
      category -> Map.put(new, "vat", stored(category.vat))
    end
  end
end
