defmodule AbakusWeb.SettingsNav do
  @moduledoc """
  The settings hub: the sections the sidebar lists in its settings mode, grouped by area. Allgemein is everyone's,
  Budget the budget owner's, Kasse its participants'; Depot is everyone's, since anyone may start a Depot there,
  with Belegeingang only once they have a portfolio. An `on_mount` hook assigns them as `@settings_groups`.
  """
  use AbakusWeb, :verified_routes

  alias Abakus.Kasse.BudgetLink
  alias AbakusWeb.Areas

  def on_mount(:default, _params, _session, socket),
    do: {:cont, assign_groups(socket)}

  @doc "Assigns the groups again, e.g. once linking the Kasse to the budget hides YNAB."
  def assign_groups(socket),
    do: Phoenix.Component.assign(socket, :settings_groups, groups(socket.assigns.current_scope))

  @doc """
  The groups the scope's user sees, each `{label, entries}`; an entry has `key`, `label`, `icon`, `path` and the
  `live_session` it opens in, since only links within one navigate.
  """
  def groups(scope) do
    [
      {"Allgemein", [access(), appearance()]},
      Areas.allowed?(scope, :budget) && {"Budget", [ynab_import()]},
      Areas.allowed?(scope, :kasse) && {"Kasse", kasse(scope)},
      {"Depot", depot(scope)}
    ]
    |> Enum.filter(& &1)
  end

  defp access,
    do: entry(:access, "Zugang", "key-round", ~p"/settings/access", :require_sudo_mode)

  defp appearance, do: entry(:appearance, "Aussehen", "palette", ~p"/settings/appearance")

  defp ynab_import, do: entry(:ynab_import, "YNAB-Import", "history", ~p"/settings/budget/ynab")

  defp kasse(scope) do
    linked? = BudgetLink.account(scope.participant) != nil

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
      scope.user.budget_owner &&
        kasse_entry(:kasse_budget, "Budget-Verknüpfung", "link", ~p"/settings/kasse/budget"),
      kasse_entry(:kasse_export, "Export", "archive", ~p"/settings/kasse/export"),
      !linked? && kasse_entry(:kasse_ynab, "YNAB", "wallet", ~p"/settings/kasse/ynab")
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

  defp kasse_entry(key, label, icon, path), do: entry(key, label, icon, path, :kasse_settings)

  defp entry(key, label, icon, path, live_session \\ :settings),
    do: %{key: key, label: label, icon: icon, path: path, live_session: live_session}
end
