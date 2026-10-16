defmodule AbakusWeb.Kasse.Components do
  @moduledoc """
  The Kasse's own pieces next to Setzkasten's components: local times, activity entries, the rename form of
  people and categories, and numbers of expenses.
  """
  use Phoenix.Component
  use Setzkasten
  use AbakusWeb, :verified_routes

  alias Abakus.Format
  alias Abakus.Kasse.Activities.Activity
  alias Phoenix.LiveView.JS

  @doc "A UTC moment in local time, `14.10.2026, 18:05`, machine-readable in `datetime`."
  attr :at, DateTime, required: true
  attr :class, :any, default: nil

  def local_time(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(DateTime.truncate(@at, :second))} class={@class}>
      {Format.datetime(@at)}
    </time>
    """
  end

  @doc """
  An entry of the activity log as a list row: who did what, the changed fields as old → new, and
  when. With `link` an entry about an expense opens it.
  """
  attr :id, :string, required: true
  attr :activity, Activity, required: true
  attr :link, :boolean, default: false

  def activity_entry(assigns) do
    activity = assigns.activity

    assigns =
      assign(assigns,
        actor: if(activity.actor, do: activity.actor.name, else: "Automatisch"),
        verb: verb(activity.action),
        details: activity.details,
        amount?: activity.action in [:expense_created, :expense_deleted],
        path:
          if(assigns.link && activity.expense_id, do: ~p"/kasse/expenses/#{activity.expense_id}")
      )

    ~H"""
    <.list_row id={@id} navigate={@path}>
      <%= if @verb do %>
        {@actor} hat „{@details.title}“ {@verb}<span
          :if={@amount? && @details.amount_cents}
          class="font-normal text-base-content/70"
        > (<.amount value={@details.amount_cents} />)</span>.
      <% else %>
        {@actor}: {@details.text || @activity.action}
      <% end %>
      <span
        :for={change <- @details.changes}
        class="mt-1 block text-sm font-normal text-base-content/70"
      >
        {change.field}: <del>{blank(change.old)}</del>
        → <ins class="text-base-content no-underline">{blank(change.new)}</ins>
      </span>
      <:meta><.local_time at={@activity.inserted_at} /></:meta>
    </.list_row>
    """
  end

  defp verb(:expense_created), do: "angelegt"
  defp verb(:expense_updated), do: "geändert"
  defp verb(:expense_deleted), do: "gelöscht"
  defp verb(_action), do: nil

  defp blank(value) when value in [nil, ""], do: "–"
  defp blank(value), do: value

  @doc """
  The name form of a person or category in a popover at its row, open while the page renders it.
  It sends `validate_rename` and `save_rename` with the params under `rename`, and
  `cancel_rename` when it closes otherwise.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true, doc: "the current name, for the title"
  attr :anchor, :string, required: true, doc: "the id of the row"
  attr :form, Phoenix.HTML.Form, required: true

  def rename_popover(assigns) do
    ~H"""
    <.popover
      id={@id}
      title={"„#{@name}“ umbenennen"}
      anchor={@anchor}
      align={:end}
      show
      on_cancel={JS.push("cancel_rename")}
    >
      <.form
        for={@form}
        id="rename-form"
        class="grid gap-3"
        phx-change="validate_rename"
        phx-submit="save_rename"
      >
        <.input
          field={@form[:name]}
          label="Name"
          required
          maxlength={Abakus.Kasse.Names.max_length()}
          autocomplete="off"
          autofocus
        />
        <div class="flex justify-end gap-2">
          <.button size={:sm} phx-click={hide_popover(@id)}>Abbrechen</.button>
          <.button type="submit" size={:sm} variant={:primary}>Speichern</.button>
        </div>
      </.form>
    </.popover>
    """
  end

  @doc ~s(A number of expenses: `"1 Ausgabe"`, `"3 Ausgaben"`.)
  @spec expense_count(non_neg_integer()) :: String.t()
  def expense_count(1), do: "1 Ausgabe"
  def expense_count(count), do: "#{count} Ausgaben"
end
