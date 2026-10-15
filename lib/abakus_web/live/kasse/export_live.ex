defmodule AbakusWeb.Kasse.ExportLive do
  @moduledoc """
  The downloads of `AbakusWeb.Kasse.ExportController` for everything or a period: all expenses
  as CSV and JSON. `?from=&to=` preset the period.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Kasse.Exports

  @downloads [
    {"expenses-csv", "CSV (Excel, Numbers)", "/kasse/export/expenses.csv"},
    {"expenses-json", "JSON", "/kasse/export/expenses.json"}
  ]

  @impl true
  def mount(params, _session, socket) do
    period = for key <- ~w(from to), into: %{}, do: {key, text(params[key])}
    {:ok, socket |> assign(page_title: "Export", downloads: @downloads) |> assign_period(period)}
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  @impl true
  def handle_event("period", params, socket),
    do: {:noreply, assign_period(socket, params)}

  defp assign_period(socket, params) do
    period = %{"from" => params["from"] || "", "to" => params["to"] || ""}

    {query, errors} =
      case Exports.period(period) do
        {:ok, _period} -> {for({key, value} <- period, value != "", do: {key, value}), []}
        {:error, message} -> {nil, [{error_field(period), {message, []}}]}
      end

    # Without the params' "_unused_" markers: an error on the field not typed in shows too.
    assign(socket, form: to_form(period, errors: errors), query: query)
  end

  defp error_field(period),
    do: if(match?({:error, _}, Exports.period(%{"from" => period["from"]})), do: :from, else: :to)

  defp href(path, []), do: path
  defp href(path, query), do: path <> "?" <> URI.encode_query(query)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.kasse
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:settings}
    >
      <.header back={~p"/kasse/settings"} back_label="Gruppe">
        Export
        <:subtitle>Ausgaben herunterladen – alles oder nur einen Zeitraum.</:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <.form for={@form} id="export-period" phx-change="period">
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:from]} type="date" label="Von" />
            <.input field={@form[:to]} type="date" label="Bis" />
          </div>
          <p class="mt-2 text-sm text-base-content/70">Leer lassen für alle Ausgaben.</p>
        </.form>

        <section aria-labelledby="export-expenses">
          <.section_heading id="export-expenses">Alle Ausgaben</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Mit Kategorie, Fremdwährung und den Anteilen aller Personen. Gelöschte Ausgaben fehlen.
          </p>
          <.download_buttons links={@downloads} query={@query} primary="expenses-csv" />
        </section>
      </div>
    </Layouts.kasse>
    """
  end

  attr :links, :list, required: true
  attr :query, :list, doc: "nil while the period is invalid"
  attr :primary, :string, default: nil

  defp download_buttons(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.button
        :for={{id, label, path} <- @links}
        id={"export-#{id}"}
        href={href(path, @query || [])}
        download
        disabled={!@query}
        variant={if id == @primary, do: :primary, else: :neutral}
        icon="download"
      >
        {label}
      </.button>
    </div>
    """
  end
end
