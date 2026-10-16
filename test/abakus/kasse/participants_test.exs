defmodule Abakus.Kasse.ParticipantsTest do
  use Abakus.DataCase

  import Abakus.Kasse.ActivityTexts
  import Abakus.KasseFixtures

  import Abakus.UsersFixtures
  import Swoosh.TestAssertions

  alias Abakus.Kasse.{Activities, Expenses, Participants}
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Users.User

  defp add(attrs),
    do: Participants.create_participant(nil, Map.put_new(attrs, :email, "x@example.com"))

  test "creates a person with a normalized name and logs it" do
    anna = person!("  Anna  ")

    assert %{name: "Anna", archived_at: nil} = Participants.get_participant!(anna.id)
    assert activity_texts(:oldest_first) == ["Person „Anna“ hinzugefügt"]
  end

  test "refuses an empty or long name and a name that exists, regardless of its case" do
    person!("Anna")

    assert {:error, changeset} = add(%{name: "   "})
    assert errors_on(changeset) == %{name: ["Bitte einen Namen für die Person angeben."]}

    assert {:error, changeset} = add(%{name: "anna"})
    assert errors_on(changeset) == %{name: ["„anna“ gibt es schon."]}

    assert {:error, changeset} = add(%{name: String.duplicate("ä", 61)})

    assert errors_on(changeset) == %{name: ["Der Name ist zu lang (höchstens 60 Zeichen)."]}

    assert activity_texts(:oldest_first) == ["Person „Anna“ hinzugefügt"]
  end

  describe "a person's user" do
    test "is created for a new email address, which is kept in lower case" do
      {:ok, dora} =
        Participants.create_participant(nil, %{name: "Dora", email: " Dora@Example.com "})

      assert %User{email: "dora@example.com", confirmed_at: nil} = dora.user
      assert Repo.get!(Participant, dora.id).user_id == dora.user.id
    end

    test "is the existing user with the email address" do
      user = user_fixture(email: "owner@example.com")

      {:ok, owner} =
        Participants.create_participant(nil, %{name: "Olga", email: "OWNER@example.com"})

      assert owner.user.id == user.id
      assert Participants.for_user(user).id == owner.id
    end

    test "is one person at most" do
      person!("Anna")

      assert {:error, changeset} =
               Participants.create_participant(nil, %{name: "Anni", email: "anna@example.com"})

      assert errors_on(changeset) == %{email: ["Diese Adresse gehört schon zu einer Person."]}
    end

    test "needs a valid email address, checked with the name" do
      assert {:error, changeset} = Participants.create_participant(nil, %{name: " "})

      assert errors_on(changeset) == %{
               name: ["Bitte einen Namen für die Person angeben."],
               email: ["Bitte eine E-Mail-Adresse angeben."]
             }

      assert {:error, changeset} =
               Participants.create_participant(nil, %{name: "Dora", email: "dora at home"})

      assert errors_on(changeset) == %{email: ["braucht ein @ und keine Leerzeichen"]}
      assert Repo.aggregate(User, :count) == 0
      assert activity_texts() == []
    end

    test "makes no person of the Kasse once the person is archived" do
      anna = person!("Anna")
      user = Repo.get!(User, anna.user_id)
      {:ok, _anna} = Participants.archive_participant(nil, anna)

      refute Participants.for_user(user)
    end
  end

  describe "inviting a person" do
    test "mails a new user a sign-in link" do
      {:ok, dora} =
        Participants.invite_participant(
          nil,
          %{name: "Dora", email: "dora@example.com"},
          &"/#{&1}"
        )

      assert_email_sent(to: [{"", "dora@example.com"}], subject: "Abakus: Einladung")
      assert dora.name == "Dora"
    end

    test "mails nobody who has signed in before" do
      user_fixture(email: "owner@example.com")
      assert_email_sent(subject: "Abakus: Anmeldelink")

      {:ok, _olga} =
        Participants.invite_participant(
          nil,
          %{name: "Olga", email: "owner@example.com"},
          &"/#{&1}"
        )

      refute_email_sent()
    end

    test "adds nobody and mails nobody when the input is wrong" do
      assert {:error, _changeset} =
               Participants.invite_participant(nil, %{name: "Dora"}, &"/#{&1}")

      refute_email_sent()
    end
  end

  test "renames a person, but not to the name of another, and logs only a real change" do
    anna = person!("Anna")
    ben = person!("Ben")

    assert {:ok, %{name: "Benedikt"} = benedikt} =
             Participants.rename_participant(anna.id, ben, %{name: " Benedikt "})

    assert {:error, changeset} =
             Participants.rename_participant(anna.id, benedikt, %{name: "ANNA"})

    assert errors_on(changeset) == %{name: ["„ANNA“ gibt es schon."]}
    assert {:ok, _same} = Participants.rename_participant(anna.id, benedikt, %{name: "Benedikt"})

    assert [%{actor_id: actor_id} | _] = Activities.list_activities()
    assert actor_id == anna.id
    assert List.last(activity_texts(:oldest_first)) == "Person „Ben“ umbenannt in „Benedikt“"
    assert length(activity_texts(:oldest_first)) == 3
  end

  test "lists people by name regardless of case, active and archived apart" do
    person!("berta")
    person!("Anna")
    cleo = person!("Cleo")
    {:ok, _cleo} = Participants.archive_participant(nil, cleo)

    assert Enum.map(Participants.list_participants(), & &1.name) == ~w(Anna berta)
    assert Enum.map(Participants.list_participants(:archived), & &1.name) == ~w(Cleo)
    assert Enum.map(Participants.list_participants(:all), & &1.name) == ~w(Anna berta Cleo)
  end

  test "archives and reactivates a person, logging both" do
    cleo = person!("Cleo")

    {:ok, archived} = Participants.archive_participant(nil, cleo)
    assert archived.archived_at
    {:ok, back} = Participants.reactivate_participant(nil, archived)
    assert back.archived_at == nil

    assert Enum.drop(activity_texts(:oldest_first), 1) == [
             "Person „Cleo“ archiviert",
             "Person „Cleo“ reaktiviert"
           ]
  end

  test "archives a person only without a balance, which deleted expenses do not change" do
    h = household()

    expense =
      h |> equal("Einkauf", 1000, "2026-08-01", h.anna, [h.anna, h.ben]) |> create!(h.anna)

    ben = Participants.get_participant!(h.ben)

    assert {:error, changeset} = Participants.archive_participant(nil, ben)

    assert errors_on(changeset) == %{
             archived_at: [
               "Ben hat noch einen Saldo von −5,00\u00A0€. Bitte erst ausgleichen, dann archivieren."
             ]
           }

    refute Participants.get_participant!(h.ben).archived_at

    assert {:ok, _cleo} =
             Participants.archive_participant(nil, Participants.get_participant!(h.cleo))

    {:ok, _deleted} = Expenses.delete_expense(h.anna, expense)
    assert {:ok, _ben} = Participants.archive_participant(nil, ben)
  end
end
