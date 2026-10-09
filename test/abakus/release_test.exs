defmodule Abakus.ReleaseTest do
  use Abakus.DataCase

  import ExUnit.CaptureIO
  import Abakus.UsersFixtures

  alias Mix.Tasks.Abakus.Invite

  test "invite/1 creates the user and mails the sign-in link of the public URL" do
    email = unique_user_email()

    assert capture_io(fn -> Abakus.Release.invite(email) end) =~ "Invited #{email}"

    assert Abakus.Users.get_user_by_email(email)
    assert_received {:email, %{subject: "Abakus: Einladung", text_body: body}}
    assert body =~ "http://localhost:4002/users/log-in/"
  end

  test "mix abakus.invite prints the link, as the dev mailbox lives in the server" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    email = unique_user_email()

    Invite.run([email])

    assert_received {:mix_shell, :info, [message]}

    assert message =~
             ~r"^Invited #{Regex.escape(email)}\. Sign-in link: http://localhost:4002/users/log-in/\S+$"

    assert_received {:email, %{subject: "Abakus: Einladung"}}

    assert_raise Mix.Error, ~r/Could not invite/, fn -> Invite.run([email]) end
    assert_raise Mix.Error, ~r/usage/, fn -> Invite.run([]) end
  end
end
