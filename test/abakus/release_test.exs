defmodule Abakus.ReleaseTest do
  use Abakus.DataCase

  import ExUnit.CaptureIO
  import Abakus.UsersFixtures

  alias Abakus.FakeYnab
  alias Abakus.Kasse.Participants
  alias Mix.Tasks.Abakus.AddParticipant
  alias Mix.Tasks.Abakus.Invite
  alias Mix.Tasks.Abakus.YnabImport, as: YnabImportTask

  @plan Path.expand("../fixtures/ynab/plan.json", __DIR__)
        |> File.read!()
        |> JSON.decode!()
        |> Map.fetch!("plan")

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

  @tag :tmp_dir
  test "import_kasse/2 imports the old app's file and names the users", %{tmp_dir: dir} do
    path = Abakus.KasseFixtures.old_app_file!(dir)

    emails = %{
      "Anna" => "anna@example.com",
      "Ben" => "ben@example.com",
      "Cleo" => "cleo@example.com"
    }

    output = capture_io(fn -> Abakus.Release.import_kasse(path, emails) end)

    assert output =~ "Imported the Kasse: "
    assert output =~ "5 expenses"
    assert output =~ "Users matched: none."
    assert output =~ "sign-in page: anna@example.com, ben@example.com, cleo@example.com."
    assert Participants.get_participant!(5).name == "Cleo"
  end

  describe "the YNAB import" do
    setup do
      FakeYnab.start(%{"plan-test" => @plan})
      previous = System.get_env("YNAB_TOKEN")
      System.put_env("YNAB_TOKEN", FakeYnab.token())

      on_exit(fn ->
        if previous,
          do: System.put_env("YNAB_TOKEN", previous),
          else: System.delete_env("YNAB_TOKEN")
      end)
    end

    test "import_ynab/1 imports with the token from the environment and prints the report" do
      output = capture_io(fn -> Abakus.Release.import_ynab() end)

      assert output =~ "Imported “Testhaushalt”: 4 accounts"
      assert output =~ "Every month, category and account matches YNAB."
    end

    test "mix abakus.ynab_import fails when the numbers differ, keeping the data" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
      plan = update_in(@plan, ["months", Access.at(0), "to_be_budgeted"], &(&1 + 10))
      FakeYnab.start(%{"other-plan" => plan})

      assert_raise Mix.Error, ~r/numbers differ/, fn -> YnabImportTask.run(["other-plan"]) end

      assert_received {:mix_shell, :info,
                       ["  2026-08, Ready to Assign: YNAB 2770.01, Abakus 2770.00"]}

      assert length(Abakus.Ledger.list_accounts()) == 4
    end

    test "mix abakus.ynab_import prints the report, and fails on errors" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      YnabImportTask.run(["plan-test"])
      assert_received {:mix_shell, :info, ["Imported “Testhaushalt”" <> _]}

      assert_raise Mix.Error, ~r/YNAB answered 404/, fn -> YnabImportTask.run(["other"]) end
      assert_raise Mix.Error, ~r/usage/, fn -> YnabImportTask.run(["a", "b"]) end

      System.delete_env("YNAB_TOKEN")
      assert_raise Mix.Error, ~r/YNAB_TOKEN is not set/, fn -> YnabImportTask.run([]) end
    end
  end
end
