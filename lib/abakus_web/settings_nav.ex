defmodule AbakusWeb.SettingsNav do
  @moduledoc """
  The settings hub: the sections the sidebar lists in its settings mode, grouped by area. Allgemein is everyone's,
  but Geräte only the budget owner's, who alone signs apps in; Kasse its participants'; Depot is everyone's, since
  anyone may start a Depot there, with Belegeingang only once they have a portfolio. An `on_mount` hook assigns them
  as `@settings_groups`.
  """
  use AbakusWeb, :verified_routes

  alias Abakus.Users.Scope
  alias AbakusWeb.Areas

  def on_mount(:default, _params, _session, socket),
    do: {:cont, assign_groups(socket)}

  @doc "Assigns the groups again, e.g. once a first portfolio shows Belegeingang."
  def assign_groups(socket),
    do: Phoenix.Component.assign(socket, :settings_groups, groups(socket.assigns.current_scope))

  @doc """
  The groups the scope's user sees, each `{label, entries}`; an entry has `key`, `label`, `plush`, `icon` (Lucide,
  where the plush has no image), `path` and the `live_session` it opens in, since only links within one navigate.
  """
  def groups(scope) do
    [
      {"Allgemein",
       Enum.filter([access(), appearance(), Scope.budget_owner?(scope) && devices()], & &1)},
      Areas.allowed?(scope, :kasse) && {"Kasse", kasse(scope)},
      {"Depot", depot(scope)}
    ]
    |> Enum.filter(& &1)
  end

  defp access do
    :access
    |> entry("Zugang", "key", ~p"/settings/access", :require_sudo_mode)
    |> Map.put(:icon, "key-round")
  end

  defp appearance, do: entry(:appearance, "Aussehen", "palette", ~p"/settings/appearance")

  defp devices, do: entry(:devices, "Geräte", "smartphone", ~p"/settings/devices")

  defp kasse(scope) do
    [
      kasse_entry(:kasse_group, "Gruppe", "house", ~p"/settings/kasse"),
      kasse_entry(:kasse_participants, "Teilnehmer", "users", ~p"/settings/kasse/participants"),
      kasse_entry(:kasse_categories, "Kategorien", "tag", ~p"/settings/kasse/categories"),
      kasse_entry(
        :kasse_recurring,
        "Wiederkehrende Ausgaben",
        "repeat",
        ~p"/settings/kasse/recurring"
      ),
      kasse_entry(:kasse_rates, "Wechselkurse", "banknote", ~p"/settings/kasse/rates"),
      Scope.budget_owner?(scope) &&
        kasse_entry(:kasse_budget, "Budget-Verknüpfung", "link", ~p"/settings/kasse/budget"),
      kasse_entry(:kasse_export, "Export", "archive", ~p"/settings/kasse/export")
    ]
    |> Enum.filter(& &1)
  end

  defp depot(scope) do
    [
      entry(:depots, "Depots", "briefcase", ~p"/settings/depot/portfolios"),
      Areas.allowed?(scope, :depot) &&
        entry(:receipt_intake, "Belegeingang", "file-text", ~p"/settings/depot/receipt-intake")
    ]
    |> Enum.filter(& &1)
  end

  defp kasse_entry(key, label, plush, path), do: entry(key, label, plush, path, :kasse_settings)

  defp entry(key, label, plush, path, live_session \\ :settings),
    do: %{
      key: key,
      label: label,
      plush: plush,
      icon: plush,
      path: path,
      live_session: live_session
    }
end
