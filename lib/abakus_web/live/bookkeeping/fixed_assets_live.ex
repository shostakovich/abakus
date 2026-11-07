defmodule AbakusWeb.Bookkeeping.FixedAssetsLive do
  @moduledoc """
  The Buchhaltung's „Anlagen“: the asset register (`Abakus.Bookkeeping.FixedAssets`), the latest purchase first,
  each with its book value today. A dialog adds or changes an asset, another records how it left the register, sold
  or withdrawn, with the payment of a sale among the transactions proposed for it.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Depreciation, Disposal, Filings, FixedAsset, FixedAssets, Vat}
  alias Abakus.{Format, LocalTime, Money}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_assets}
    >
      <.header>
        Anlagen
        <:subtitle>
          Linear nach Monaten abgeschrieben; bis 800 € netto als geringwertiges Wirtschaftsgut sofort.
        </:subtitle>
        <:actions>
          <.button
            id="asset-new"
            variant={:primary}
            icon="plus"
            class="max-md:hidden"
            phx-click="new"
          >
            Neue Anlage
          </.button>
        </:actions>
      </.header>
      <.list :if={@assets != []} id="assets">
        <.list_row
          :for={asset <- @assets}
          id={"asset-#{asset.id}"}
          title={asset.name}
          on_click={JS.push("edit", value: %{id: asset.id})}
          muted={asset.disposal != nil}
          menu={:always}
          trailing_on_phone={:title}
        >
          <:meta>
            {join_meta([
              "gekauft #{Format.date(asset.purchased_on)}",
              "#{Money.euros(asset.net)} netto",
              life_text(asset)
            ])}
          </:meta>
          <:meta :if={asset.disposal}>{disposal_text(asset.disposal)}</:meta>
          <:trailing :let={_place}>
            <div class="text-end">
              <.amount value={Depreciation.current_value(asset, @today)} />
              <div class="text-xs text-base-content/70">Buchwert</div>
            </div>
          </:trailing>
          <:action
            id={"asset-#{asset.id}-dispose"}
            label={if asset.disposal, do: "Abgang bearbeiten", else: "Abgang erfassen"}
            icon="archive"
            on_click={JS.push("dispose", value: %{id: asset.id})}
          />
          <:action
            :if={asset.disposal}
            id={"asset-#{asset.id}-undispose"}
            label="Abgang zurücknehmen"
            icon="rotate-ccw"
            confirm="Abgang zurücknehmen?"
            confirm_text={"„#{asset.name}“ ist dann wieder im Anlagenverzeichnis."}
            confirm_label="Zurücknehmen"
            on_click={JS.push("undispose", value: %{id: asset.id})}
          />
          <:action
            id={"asset-#{asset.id}-delete"}
            label="Löschen"
            icon="trash-2"
            danger
            confirm={"„#{asset.name}“ löschen?"}
            confirm_text="Die Anlage zählt dann in keiner EÜR und keiner Umsatzsteuer mehr."
            confirm_label="Löschen"
            on_click={JS.push("delete", value: %{id: asset.id})}
          />
        </.list_row>
      </.list>
      <.empty_state
        :if={@assets == []}
        id="assets-empty"
        layout={:page}
        plush="package"
        icon="package"
        title="Noch keine Anlagen"
      >
        Eine Anschaffung, die länger als ein Jahr genutzt wird, kommt mit ihrer Nutzungsdauer ins
        Anlagenverzeichnis und zählt in der EÜR mit ihrer Abschreibung.
      </.empty_state>
      <:fab><.fab id="fab-asset" label="Neue Anlage" phx-click="new" /></:fab>

      <.modal
        :if={@asset_form}
        id="asset-modal"
        show
        title={if @editing.id, do: "Anlage bearbeiten", else: "Neue Anlage"}
        on_cancel={JS.push("close")}
      >
        <.form for={@asset_form} id="asset-form" phx-change="validate" phx-submit="save">
          <.input field={@asset_form[:name]} label="Bezeichnung" autocomplete="off" />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@asset_form[:purchased_on]} type="date" label="Angeschafft am" />
            <.input
              field={@asset_form[:net]}
              label="Anschaffungskosten netto"
              numeric
              inputmode="decimal"
              suffix="€"
              value={amount_value(@asset_form[:net].value)}
            />
          </div>
          <.input
            field={@asset_form[:useful_life]}
            label="Nutzungsdauer"
            suffix="Jahre"
            numeric
            inputmode="numeric"
            class="max-w-40"
            help="Nach der AfA-Tabelle; bis 800 € netto ohne, das Wirtschaftsgut wird sofort abgeschrieben."
          />
          <.action_bar sticky>
            <.button phx-click={hide_modal("asset-modal")}>Abbrechen</.button>
            <.button id="asset-save" type="submit" variant={:primary} phx-disable-with="Speichern …">
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </.modal>

      <.modal
        :if={@disposal_form}
        id="disposal-modal"
        show
        title={"Abgang: #{@editing.name}"}
        on_cancel={JS.push("close")}
      >
        <.form
          for={@disposal_form}
          id="disposal-form"
          phx-change="validate_disposal"
          phx-submit="save_disposal"
        >
          <.input
            field={@disposal_form[:kind]}
            type="radio_group"
            label="Art"
            options={[
              %{label: "Verkauf", value: "sale", description: "Auch eine Inzahlungnahme"},
              %{
                label: "Entnahme",
                value: "withdrawal",
                description: "Ins Privatvermögen, zum Teilwert"
              }
            ]}
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@disposal_form[:date]} type="date" label="Datum" />
            <.input
              field={@disposal_form[:vat]}
              type="select"
              label="Umsatzsteuer"
              options={for t <- Disposal.treatments(), do: {Vat.label(t), Vat.stored()[t]}}
            />
          </div>
          <.input
            field={@disposal_form[:amount]}
            label={
              if @disposal.kind == :withdrawal,
                do: "Teilwert inkl. Umsatzsteuer",
                else: "Erlös inkl. Umsatzsteuer"
            }
            numeric
            inputmode="decimal"
            suffix="€"
            value={amount_value(@disposal_form[:amount].value)}
          />
          <.input
            :if={@disposal.kind == :sale}
            field={@disposal_form[:transaction_id]}
            type="select"
            label="Zahlung"
            options={[
              {"Keine, etwa bei Inzahlungnahme", ""}
              | Enum.map(@proposals, &{payment_label(&1), &1.id})
            ]}
            help="Eingänge über den Erlös auf einem Geschäftskonto, einen Monat vor oder nach dem Datum. Die Zahlung zählt dann über den Abgang."
          />
          <dl
            :if={@disposal.date}
            id="disposal-book-value"
            class="mt-2 grid grid-cols-[1fr_auto] gap-x-6 text-sm"
          >
            <dt>Restbuchwert am {Format.date(@disposal.date)}</dt>
            <dd class="text-end tabular-nums">
              {Money.euros(Depreciation.book_value(%{@editing | disposal: nil}, @disposal.date))}
            </dd>
          </dl>
          <.action_bar sticky>
            <.button phx-click={hide_modal("disposal-modal")}>Abbrechen</.button>
            <.button
              id="disposal-save"
              type="submit"
              variant={:primary}
              phx-disable-with="Speichern …"
            >
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp life_text(%FixedAsset{net: net, useful_life: years}) do
    cond do
      Depreciation.low_value?(net) -> "geringwertig"
      years == 1 -> "1 Jahr"
      true -> "#{years} Jahre"
    end
  end

  defp disposal_text(%Disposal{kind: :sale} = disposal),
    do: "verkauft am #{Format.date(disposal.date)} für #{Money.euros(disposal.amount)}"

  defp disposal_text(%Disposal{kind: :withdrawal} = disposal),
    do: "entnommen am #{Format.date(disposal.date)} zu #{Money.euros(disposal.amount)}"

  defp payment_label(%{payee: %{name: name}} = transaction),
    do: "#{Format.date(transaction.date)} · #{name} · #{Money.euros(transaction.amount)}"

  defp payment_label(transaction),
    do: "#{Format.date(transaction.date)} · #{Money.euros(transaction.amount)}"

  defp amount_value(cents) when is_integer(cents), do: Money.amount(cents)
  defp amount_value(text), do: text

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Anlagen", today: LocalTime.today())
     |> close()
     |> load()}
  end

  defp load(socket), do: assign(socket, :assets, FixedAssets.list(socket.assigns.current_scope))

  defp close(socket),
    do:
      assign(socket,
        asset_form: nil,
        disposal_form: nil,
        editing: nil,
        disposal: nil,
        proposals: []
      )

  @impl true
  def handle_event("new", _params, socket), do: {:noreply, open(socket, %FixedAsset{})}

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, with_asset(socket, id, &open/2)}

  def handle_event("dispose", %{"id" => id}, socket),
    do: {:noreply, with_asset(socket, id, &open_disposal/2)}

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("validate", %{"fixed_asset" => params}, socket) do
    changeset = FixedAssets.change(socket.assigns.editing, params)
    {:noreply, assign(socket, :asset_form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"fixed_asset" => params}, socket) do
    case save(socket.assigns.current_scope, socket.assigns.editing, params) do
      {:ok, asset} ->
        {:noreply,
         socket |> put_flash(:info, "„#{asset.name}“ gespeichert.") |> close() |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :asset_form, to_form(changeset))}
    end
  end

  def handle_event("validate_disposal", %{"disposal" => params}, socket) do
    changeset = FixedAssets.change_disposal(socket.assigns.editing, params)
    {:noreply, socket |> assign_disposal(changeset) |> assign_disposal_form(changeset, :validate)}
  end

  def handle_event("save_disposal", %{"disposal" => params}, socket) do
    asset = socket.assigns.editing

    case FixedAssets.record_disposal(socket.assigns.current_scope, asset, params) do
      {:ok, asset} ->
        {:noreply,
         socket
         |> put_flash(:info, "Abgang von „#{asset.name}“ gespeichert.")
         |> close()
         |> load()}

      {:error, changeset} ->
        {:noreply,
         socket |> assign_disposal(changeset) |> assign_disposal_form(changeset, :insert)}
    end
  end

  def handle_event("undispose", %{"id" => id}, socket) do
    {:noreply,
     with_asset(socket, id, fn socket, asset ->
       case FixedAssets.remove_disposal(socket.assigns.current_scope, asset) do
         {:ok, asset} ->
           socket
           |> put_flash(:info, "„#{asset.name}“ ist wieder im Anlagenverzeichnis.")
           |> load()

         {:error, :locked} ->
           put_flash(
             socket,
             :error,
             "#{Filings.locked_message()}: Der Abgang zählt in einer gesendeten Voranmeldung."
           )
       end
     end)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:noreply,
     with_asset(socket, id, fn socket, asset ->
       case FixedAssets.delete(socket.assigns.current_scope, asset) do
         {:ok, _asset} ->
           socket |> put_flash(:info, "„#{asset.name}“ gelöscht.") |> load()

         {:error, :locked} ->
           put_flash(
             socket,
             :error,
             "#{Filings.locked_message()}: Der Abgang zählt in einer gesendeten Voranmeldung."
           )
       end
     end)}
  end

  defp with_asset(socket, id, fun) do
    case FixedAssets.get(socket.assigns.current_scope, id) do
      nil -> socket |> put_flash(:error, "Anlage nicht gefunden.") |> close() |> load()
      asset -> fun.(socket, asset)
    end
  end

  defp save(scope, %FixedAsset{id: nil}, params), do: FixedAssets.create(scope, params)
  defp save(scope, asset, params), do: FixedAssets.update(scope, asset, params)

  defp open(socket, asset),
    do: assign(socket, editing: asset, asset_form: to_form(FixedAssets.change(asset)))

  defp open_disposal(socket, asset) do
    changeset = FixedAssets.change_disposal(asset)

    socket
    |> assign(editing: asset)
    |> assign_disposal(changeset)
    |> assign_disposal_form(changeset, nil)
  end

  defp assign_disposal(socket, changeset) do
    disposal = Ecto.Changeset.apply_changes(changeset)

    assign(socket,
      disposal: disposal,
      proposals: FixedAssets.payment_proposals(socket.assigns.current_scope, disposal)
    )
  end

  defp assign_disposal_form(socket, changeset, action),
    do: assign(socket, :disposal_form, to_form(changeset, action: action))
end
