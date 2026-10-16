defmodule AbakusWeb.BudgetLive.MonthDetails do
  @moduledoc """
  A month's details in a popover from its card, as Actual's month menu: how Zu verteilen adds up (with the later
  months it does not cover), the summary, the month's need and what later months have assigned.
  """
  use AbakusWeb, :html

  import Abakus.Format, only: [month_year: 1]

  alias Abakus.Budget.Month
  alias AbakusWeb.BudgetLive.{Components, Status, Window}

  @doc "The later months among `months` that have money assigned, as `{month, assigned}`."
  def future(months, %Month{month: month}),
    do: for(m <- months, Date.after?(m.month, month), m.assigned != 0, do: {m.month, m.assigned})

  attr :id, :string, required: true
  attr :anchor, :string, required: true
  attr :month, Month, required: true
  attr :future, :list, required: true

  @doc "The popover, placed at `anchor`."
  def details(assigns) do
    ~H"""
    <.popover id={@id} anchor={@anchor} title={month_year(@month.month)} class="app-mpop">
      <div class="app-mdetails">
        <.ready_section month={@month} />
        <.summary_section month={@month} />
        <.need_section month={@month} />
        <.future_section month={@month} future={@future} />
      </div>
    </.popover>
    """
  end

  attr :month, Month, required: true

  defp ready_section(assigns) do
    assigns = assign(assigns, :ready, Status.ready(assigns.month))

    ~H"""
    <section id={"#{key(@month)}-ready"}>
      <.description_list>
        <:item :for={line <- Status.calculation(@month)} label={line.label}>
          <.amount value={line.value} class={Components.tone_class(line.tone)} />
        </:item>
        <:item label={elem(@ready, 1)} total>
          <.amount
            value={@month.ready_to_assign_shown}
            class={Components.tone_class(elem(@ready, 0))}
          />
        </:item>
      </.description_list>
      <.alert :if={@month.uncovered != []} tone={:warning} class="app-uncovered-alert mt-3">
        <p :for={line <- Status.uncovered(@month)}>{line}</p>
      </.alert>
    </section>
    """
  end

  attr :month, Month, required: true

  defp summary_section(assigns) do
    ~H"""
    <section id={"#{key(@month)}-summary"}>
      <.section_heading level={3} size={:sm}>Zusammenfassung</.section_heading>
      <.description_list>
        <:item label="Übrig aus Vormonat"><.amount value={@month.carried} /></:item>
        <:item label="Zugewiesen"><.amount value={@month.assigned} /></:item>
        <:item label="Aktivität"><.amount value={@month.activity} /></:item>
        <:item label="Verfügbar" total><.amount value={@month.available} /></:item>
      </.description_list>
    </section>
    """
  end

  attr :month, Month, required: true

  defp need_section(assigns) do
    ~H"""
    <section id={"#{key(@month)}-need"}>
      <.section_heading level={3} size={:sm}>Monatsbedarf</.section_heading>
      <.description_list>
        <:item label="Ziele"><.amount value={@month.needed} /></:item>
        <:item :if={@month.underfunded > 0} label="Noch offen" strong>
          <.amount value={@month.underfunded} />
        </:item>
      </.description_list>
    </section>
    """
  end

  attr :month, Month, required: true
  attr :future, :list, required: true

  defp future_section(assigns) do
    ~H"""
    <section id={"#{key(@month)}-future"}>
      <.section_heading level={3} size={:sm}>Künftige Monate</.section_heading>
      <.description_list :if={@future != []}>
        <:item label="Insgesamt" strong><.amount value={@month.assigned_in_future} /></:item>
        <:item :for={{month, assigned} <- @future} label={month_year(month)}>
          <.amount value={assigned} />
        </:item>
      </.description_list>
      <p :if={@future == []} class="text-sm text-base-content/70">Nichts im Voraus verteilt.</p>
    </section>
    """
  end

  defp key(month), do: "month-#{Window.param(month.month)}"
end
