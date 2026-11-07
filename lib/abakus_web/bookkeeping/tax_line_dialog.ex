defmodule AbakusWeb.Bookkeeping.TaxLineDialog do
  @moduledoc """
  The dialog „Buchhaltung“ for one transaction: a Kategorie and its Umsatzsteuer per side (the transaction, or each
  part of a split), with the net and VAT amount they make; choosing a category sets its usual VAT treatment, and
  „Keine“ removes the side's tax line. „Kein Beleg nötig“ marks a transaction that needs no receipt. Beside the form
  are its receipts (`AbakusWeb.Bookkeeping.ReceiptPane`), which change at once, not on saving. With `next` the
  button reads „Speichern und weiter“. Tells its LiveView `{TaxLineDialog, :done, transaction_id}` once saved, or
  once the transaction is gone; `close_tax_lines` goes to the LiveView itself.
  """
  use AbakusWeb, :live_component

  alias Abakus.{Bookkeeping, Format, Money}
  alias Abakus.Bookkeeping.{Attachments, Category, Vat}
  alias AbakusWeb.Bookkeeping.ReceiptPane

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
        class="sm:max-w-6xl"
        on_cancel={JS.push("close_tax_lines")}
      >
        <p id="tax-lines-transaction" class="mb-3 text-sm text-base-content/70">
          {join_meta([
            Format.date(@transaction.date),
            payee_name(@transaction),
            Money.euros(@transaction.amount, signed: true)
          ])}
        </p>
        <div class="grid gap-6 lg:grid-cols-[3fr_2fr]">
          <.live_component
            module={ReceiptPane}
            id="receipts"
            current_scope={@current_scope}
            transaction={@transaction}
          />
          <.form
            for={%{}}
            id="tax-lines-form"
            class="flex min-w-0 flex-col gap-4"
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
              <p
                :if={side.amounts}
                id={"tax-#{side.key}-amounts"}
                class="text-sm text-base-content/70"
              >
                Netto {Money.euros(side.amounts.net, signed: true)} · USt {Money.euros(
                  side.amounts.vat,
                  signed: true
                )}
              </p>
            </fieldset>
            <.input
              :if={@receipts?}
              id="tax-lines-no-receipt"
              type="checkbox"
              name="no_receipt"
              label="Kein Beleg nötig"
              checked={@no_receipt}
              help="Etwa für eine Gebühr der Bank."
            />
            <.action_bar sticky>
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
        </div>
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

  @doc "The name of a split's part: its payee, else its memo, else the transaction's payee."
  def part_name(%{payee: %{name: name}}, _transaction), do: name
  def part_name(%{memo: memo}, _transaction) when memo not in [nil, ""], do: memo
  def part_name(_part, transaction), do: payee_name(transaction)

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

    assign(socket,
      transaction: transaction,
      sides: sides,
      params: params,
      errors: %{},
      receipts?: Attachments.sides(transaction) != [],
      no_receipt:
        transaction.id in Attachments.waived(socket.assigns.current_scope, [transaction])
    )
  end

  @impl true
  def handle_event("change", form, socket) do
    sides = form["sides"] || %{}

    params =
      Map.new(socket.assigns.params, fn {key, old} ->
        {key, follow_category(old, Map.get(sides, key, old))}
      end)

    {:noreply, assign(socket, params: params, no_receipt: no_receipt?(form, socket))}
  end

  def handle_event("save", form, socket) do
    %{current_scope: scope, transaction: transaction} = socket.assigns
    sides = form["sides"] || %{}

    case Bookkeeping.save_tax_lines(scope, transaction, sides) do
      {:error, :not_found} ->
        done(socket)

      {:error, errors} ->
        {:noreply,
         assign(socket, params: sides, errors: errors, no_receipt: no_receipt?(form, socket))}

      {:ok, _lines} ->
        if socket.assigns.receipts?,
          do: :ok = Attachments.waive(scope, transaction, no_receipt?(form, socket))

        done(socket)
    end
  end

  defp done(socket) do
    send(self(), {__MODULE__, :done, socket.assigns.transaction.id})
    {:noreply, socket}
  end

  defp no_receipt?(%{"no_receipt" => value}, _socket), do: value == "true"
  defp no_receipt?(_form, socket), do: socket.assigns.no_receipt

  defp follow_category(%{"category" => key}, %{"category" => key} = new), do: new

  defp follow_category(_old, %{"category" => key} = new) do
    case Category.get(key) do
      nil -> new
      category -> Map.put(new, "vat", stored(category.vat))
    end
  end
end
