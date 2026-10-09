defmodule Abakus.Release do
  @moduledoc "Tasks run from the release, where Mix is not available."

  alias Abakus.YnabImport
  alias Abakus.YnabImport.Report

  @app :abakus

  # A second connection would race the first to switch an empty file to WAL.
  @repo_opts [pool_size: 1]

  def migrate do
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true), @repo_opts)
    end

    :ok
  end

  @doc """
  Invites a user, who gets a sign-in link by mail:
  `bin/abakus eval 'Abakus.Release.invite("name@example.com")'`.
  """
  def invite(email) do
    start_without_server()

    case Abakus.Users.invite_user(email, &AbakusWeb.UserAuth.magic_link_url/1) do
      {:ok, user} ->
        IO.puts("Invited #{user.email}; the mail with the sign-in link is on its way.")

      {:error, :mail_not_delivered, user} ->
        IO.puts(:stderr, "Created #{user.email}, but the mail failed; see the log above.")
        IO.puts(:stderr, "Once mail works, they can request a link on the sign-in page.")
        System.halt(1)

      {:error, changeset} ->
        IO.puts(:stderr, "Could not invite #{email}: #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  @doc """
  Replaces the budget with a YNAB plan and checks the numbers (`Abakus.YnabImport`), with the token passed to
  this command only: `docker compose exec -e YNAB_TOKEN=… abakus bin/abakus eval 'Abakus.Release.import_ynab()'`;
  with several plans, pass the plan's id. Exits with 1 when it did not run or the numbers differ.
  """
  def import_ynab(plan_id \\ nil) do
    start_without_server()

    result = with {:ok, token} <- YnabImport.token(), do: YnabImport.run(token, plan_id)

    case result do
      {:ok, report} ->
        Enum.each(Report.lines(report), &IO.puts/1)
        if report.differences != [], do: System.halt(1)

      {:error, reason} ->
        Enum.each(YnabImport.error_lines(reason), &IO.puts(:stderr, &1))
        System.halt(1)
    end
  end

  # The endpoint's URL is needed (links in mails), but the container's server already holds the port.
  defp start_without_server do
    Application.load(@app)

    endpoint = Application.get_env(@app, AbakusWeb.Endpoint, [])
    Application.put_env(@app, AbakusWeb.Endpoint, Keyword.put(endpoint, :server, false))

    Application.put_env(
      @app,
      Abakus.Repo,
      Keyword.merge(Application.get_env(@app, Abakus.Repo), @repo_opts)
    )

    {:ok, _apps} = Application.ensure_all_started(@app)
  end
end
