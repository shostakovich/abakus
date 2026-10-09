defmodule Mix.Tasks.Abakus.Invite do
  @shortdoc "Invites a user: mix abakus.invite EMAIL"
  @moduledoc """
  Creates a user, mails them a sign-in link and prints the link as well: in development the
  mail stays in this task's local mailbox.

      mix abakus.invite name@example.com

  In the container: `bin/abakus eval 'Abakus.Release.invite("…")'`.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run([email]) do
    url_fun = fn token ->
      url = AbakusWeb.UserAuth.magic_link_url(token)
      send(self(), {:magic_link, url})
      url
    end

    case Abakus.Users.invite_user(email, url_fun) do
      {:ok, user} ->
        receive do
          {:magic_link, url} -> Mix.shell().info("Invited #{user.email}. Sign-in link: #{url}")
        end

      {:error, :mail_not_delivered, user} ->
        Mix.raise("Created #{user.email}, but the mail could not be sent.")

      {:error, changeset} ->
        Mix.raise("Could not invite #{email}: #{inspect(changeset.errors)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix abakus.invite EMAIL")
end
