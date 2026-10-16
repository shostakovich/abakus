defmodule AbakusWeb.Depot.Benchmark do
  @moduledoc """
  Showing or hiding the user's benchmark on Vermögen and the performance screen, a choice of
  the device: hidden by default, the browser keeps the choice and sends it when a page connects
  (`assets/js/benchmark.js`). An `on_mount` hook assigns it as `@benchmark_shown` and handles the
  button's `"toggle_benchmark"`.
  """
  use Phoenix.Component

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_params: 1, push_event: 3]

  import Setzkasten.Components.Actions, only: [button: 1]

  alias Abakus.Format

  def on_mount(:default, _params, _session, socket) do
    shown = connected?(socket) and get_connect_params(socket)["benchmark"] == "shown"

    {:cont,
     socket
     |> assign(:benchmark_shown, shown)
     |> attach_hook(:benchmark, :handle_event, &toggle/3)}
  end

  defp toggle("toggle_benchmark", _params, socket) do
    shown = not socket.assigns.benchmark_shown

    {:halt,
     socket
     |> assign(:benchmark_shown, shown)
     |> push_event("benchmark", %{shown: shown})}
  end

  defp toggle(_event, _params, socket), do: {:cont, socket}

  attr :shown, :boolean, required: true

  @doc """
  The button „Benchmark“ that shows or hides the benchmark, pressed like a selected segment
  while shown, with the key of its line.
  """
  def toggle_button(assigns) do
    ~H"""
    <.button
      id="benchmark-toggle"
      size={:sm}
      variant={if @shown, do: :primary, else: :neutral}
      aria-pressed={to_string(@shown)}
      phx-click="toggle_benchmark"
    >
      <.key />Benchmark
    </.button>
    """
  end

  attr :benchmark, :map, required: true, doc: "`%{security, ttwror}`"

  @doc """
  The benchmark's TTWROR beside its label, its name on the next line, cut short when it does not
  fit.
  """
  def note(assigns) do
    assigns = assign(assigns, :figure, Format.signed_rate(assigns.benchmark.ttwror))

    ~H"""
    <span id="benchmark-ttwror" class="flex min-w-0 flex-col">
      <span class="inline-flex items-center gap-1.5 whitespace-nowrap">
        <.key />Benchmark <span class="tabular-nums">{@figure}</span>
      </span>
      <span class="truncate" title={@benchmark.security.name}>
        {short_name(@benchmark.security.name)}
      </span>
    </span>
    """
  end

  # The key of the benchmark's line, chart series 2, drawn as `<.legend>` draws a line marker.
  defp key(assigns) do
    ~H"""
    <svg class="h-2.5 w-4 shrink-0 stroke-chart-2" viewBox="0 0 16 10" aria-hidden="true">
      <line x1="0" y1="5" x2="16" y2="5" stroke-width="2" />
    </svg>
    """
  end

  @doc "The key of the shadow portfolio's line on the net worth chart, for `<.legend>`."
  def legend_item(security), do: %{label: short_name(security.name), color: 2, marker: :line}

  @doc """
  The name without what most fund names end with, such as „UCITS ETF USD (Acc)“, a last „ETF“
  with its currency or „(Dist)“, so that a note shows the part that tells funds apart.
  """
  def short_name(name) do
    suffix = ~r/\s+(UCITS\b.*|ETF(\s+(?-i:[A-Z]{3}))?(\s+\([^()]*\))?|\([^()]*\))$/i

    case name |> String.replace(suffix, "") |> String.trim() do
      "" -> name
      short -> short
    end
  end
end
