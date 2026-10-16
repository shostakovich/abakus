defmodule Abakus.Release do
  @moduledoc "Tasks run from the release, where Mix is not available."

  alias Abakus.Depot
  alias Abakus.Kasse
  alias Abakus.Kasse.Participants
  alias Abakus.Users.Scope
  alias Abakus.YnabImport
  alias Abakus.YnabImport.Report
  alias AbakusWeb.UserAuth

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
  Adds a person to the Kasse as the user with this email address, inviting a new user by mail:
  `bin/abakus eval 'Abakus.Release.add_participant("name@example.com", "Name")'`.
  """
  def add_participant(email, name) do
    start_without_server()

    case Participants.invite_participant(
           Scope.system(),
           %{email: email, name: name},
           &UserAuth.magic_link_url/1
         ) do
      {:ok, participant} ->
        IO.puts("Added #{participant.name} (#{participant.user.email}) to the Kasse.")

      {:error, :mail_not_delivered, participant} ->
        IO.puts(
          :stderr,
          "Added #{participant.name}, but the invitation failed; see the log above."
        )

        System.halt(1)

      {:error, changeset} ->
        IO.puts(:stderr, "Could not add #{name}: #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  @doc """
  Imports the former shared-expenses app's database file into the empty Kasse once, keeping its ids
  (`Abakus.Kasse.Import`), with each person's email address by name; users missing in Abakus are created without
  mail: `bin/abakus eval 'Abakus.Release.import_kasse("/app/data/old.sqlite3", %{"Name" => "name@example.com"})'`.
  """
  def import_kasse(path, emails) do
    start_without_server()

    case Kasse.Import.run(Scope.system(), path, emails) do
      {:ok, report} ->
        rows = Enum.map_join(report.rows, ", ", fn {table, count} -> "#{count} #{table}" end)
        IO.puts("Imported the Kasse: #{rows}.")
        IO.puts("Users matched: #{list(report.matched)}.")

        IO.puts(
          "Users created, who ask for a sign-in link on the sign-in page: #{list(report.created)}."
        )

      {:error, reason} ->
        IO.puts(:stderr, "Could not import the Kasse: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Imports the former portfolio app's database file into the empty Depot once, keeping its ids
  (`Abakus.Depot.Import`), with the receipt files from the `receipts` folder next to it; each user becomes the user
  with the same email address, and users missing in Abakus are created without mail:
  `bin/abakus eval 'Abakus.Release.import_depot("/app/data/zipfelfolio/zipfelfolio.sqlite3")'`.
  """
  def import_depot(path) do
    start_without_server()

    case Depot.Import.run(path) do
      {:ok, report} ->
        rows = Enum.map_join(report.rows, ", ", fn {table, count} -> "#{count} #{table}" end)
        IO.puts("Imported the Depot: #{rows}, #{report.receipt_files} receipt files.")
        IO.puts("Users matched: #{list(report.matched)}.")

        IO.puts(
          "Users created, who ask for a sign-in link on the sign-in page: #{list(report.created)}."
        )

        IO.puts(
          "Passkeys of the old address stay behind; add them again under Einstellungen › Zugang."
        )

      {:error, reason} ->
        IO.puts(:stderr, "Could not import the Depot: #{reason}")
        System.halt(1)
    end
  end

  defp list([]), do: "none"
  defp list(emails), do: Enum.join(emails, ", ")

  @doc """
  Replaces the budget with a YNAB plan and checks the numbers (`Abakus.YnabImport`), with the token passed to
  this command only: `docker compose exec -e YNAB_TOKEN=… abakus bin/abakus eval 'Abakus.Release.import_ynab()'`;
  with several plans, pass the plan's id. Exits with 1 when it did not run or the numbers differ.
  """
  def import_ynab(plan_id \\ nil) do
    start_without_server()

    result =
      with {:ok, token} <- YnabImport.token(), do: YnabImport.run(Scope.system(), token, plan_id)

    case result do
      {:ok, report} ->
        Enum.each(Report.lines(report), &IO.puts/1)
        if report.differences != [], do: System.halt(1)

      {:error, reason} ->
        Enum.each(YnabImport.error_lines(reason), &IO.puts(:stderr, &1))
        System.halt(1)
    end
  end

  # The endpoint's URL is needed (links in mails), but the container's server already holds the port and runs the
  # background jobs.
  defp start_without_server do
    Application.load(@app)
    Application.put_env(@app, :jobs, false)

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
