defmodule Abakus.Release do
  @moduledoc "Tasks run from the release, where Mix is not available."

  alias Abakus.Kasse.Participants
  alias Abakus.Users.Scope
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
