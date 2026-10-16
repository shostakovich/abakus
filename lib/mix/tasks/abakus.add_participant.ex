defmodule Mix.Tasks.Abakus.AddParticipant do
  @shortdoc "Adds a person to the Kasse: mix abakus.add_participant EMAIL NAME"
  @moduledoc """
  Makes the user with this email address a person of the Kasse, creating and inviting them if they are new, and
  prints the sign-in link of the invitation: in development the mail stays in this task's local mailbox.

      mix abakus.add_participant name@example.com "Name"

  In the container: `bin/abakus eval 'Abakus.Release.add_participant("…", "…")'`.
  """
  use Mix.Task

  alias Abakus.Kasse.Participants
  alias Abakus.Users.Scope

  @requirements ["app.start"]

  @impl true
  def run([email, name]) do
    url_fun = fn token ->
      url = AbakusWeb.UserAuth.magic_link_url(token)
      send(self(), {:magic_link, url})
      url
    end

    case Participants.invite_participant(Scope.system(), %{email: email, name: name}, url_fun) do
      {:ok, participant} ->
        Mix.shell().info("Added #{participant.name} to the Kasse." <> link_text())

      {:error, :mail_not_delivered, participant} ->
        Mix.raise("Added #{participant.name}, but the mail could not be sent.")

      {:error, changeset} ->
        Mix.raise("Could not add #{name}: #{inspect(changeset.errors)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix abakus.add_participant EMAIL NAME")

  defp link_text do
    receive do
      {:magic_link, url} -> " Sign-in link: #{url}"
    after
      0 -> ""
    end
  end
end
