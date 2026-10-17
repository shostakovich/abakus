defmodule Abakus.ReleaseTest do
  use Abakus.DataCase

  import ExUnit.CaptureIO
  import Abakus.UsersFixtures

  alias Abakus.Kasse.Participants
  alias Mix.Tasks.Abakus.AddParticipant
  alias Mix.Tasks.Abakus.Invite

  test "invite/1 creates the user and mails the sign-in link of the public URL" do
    email = unique_user_email()

    assert capture_io(fn -> Abakus.Release.invite(email) end) =~ "Invited #{email}"

    assert Abakus.Users.get_user_by_email(email)
    assert_received {:email, %{subject: "Abakus: Einladung", text_body: body}}
    assert body =~ "http://localhost:4002/users/log-in/"
  end

  test "a task leaves the background jobs to the running server" do
    Application.put_env(:abakus, :jobs, true)
    on_exit(fn -> Application.put_env(:abakus, :jobs, false) end)

    capture_io(fn -> Abakus.Release.invite(unique_user_email()) end)

    refute Application.fetch_env!(:abakus, :jobs)
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

  test "add_participant/2 adds the person and invites their new user" do
    email = unique_user_email()

    assert capture_io(fn -> Abakus.Release.add_participant(email, "Dora") end) =~
             "Added Dora (#{email}) to the Kasse."

    assert %{name: "Dora"} =
             Participants.for_user(Abakus.Users.get_user_by_email(email))

    assert_received {:email, %{subject: "Abakus: Einladung", text_body: body}}
    assert body =~ "http://localhost:4002/users/log-in/"
  end

  test "mix abakus.add_participant prints the link of a new user and makes an existing one a person" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    AddParticipant.run(["dora@example.com", "Dora"])

    assert_received {:mix_shell, :info, [message]}

    assert message =~
             ~r"^Added Dora to the Kasse\. Sign-in link: http://localhost:4002/users/log-in/\S+$"

    user = user_fixture()
    AddParticipant.run([user.email, "Olga"])
    assert_received {:mix_shell, :info, ["Added Olga to the Kasse."]}

    assert_raise Mix.Error, ~r/Could not add/, fn ->
      AddParticipant.run([user.email, "Olga 2"])
    end

    assert_raise Mix.Error, ~r/usage/, fn -> AddParticipant.run(["dora@example.com"]) end
  end
end
