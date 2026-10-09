defmodule Mix.Tasks.Abakus.YnabImport do
  @shortdoc "Replaces the budget with a YNAB plan: mix abakus.ynab_import [PLAN_ID]"
  @moduledoc """
  Replaces the whole budget with a YNAB plan and checks Abakus's numbers against YNAB's (`Abakus.YnabImport`).
  The personal access token comes from `YNAB_TOKEN`; with several plans, pass the plan's id.

      YNAB_TOKEN=… mix abakus.ynab_import

  In the container: `docker compose exec -e YNAB_TOKEN=… abakus bin/abakus eval 'Abakus.Release.import_ynab()'`.
  """
  use Mix.Task

  alias Abakus.YnabImport
  alias Abakus.YnabImport.Report

  @requirements ["app.start"]

  @impl true
  def run(args) when length(args) <= 1 do
    result = with {:ok, token} <- YnabImport.token(), do: YnabImport.run(token, List.first(args))

    case result do
      {:ok, report} ->
        Enum.each(Report.lines(report), &Mix.shell().info(&1))

        if report.differences != [],
          do: Mix.raise("The numbers differ from YNAB; the data stays for a look.")

      {:error, reason} ->
        Mix.raise(Enum.join(YnabImport.error_lines(reason), "\n"))
    end
  end

  def run(_args), do: Mix.raise("usage: mix abakus.ynab_import [PLAN_ID]")
end
