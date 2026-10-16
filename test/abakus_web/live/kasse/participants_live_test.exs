defmodule AbakusWeb.Kasse.ParticipantsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Kasse.ActivityTexts
  import Abakus.KasseFixtures
  import AbakusWeb.PageText

  alias Abakus.Kasse.Participants

  setup %{conn: conn} do
    h = household()
    %{h: h, conn: log_in_participant(conn, h.anna)}
  end

  defp add(view, name, email),
    do: view |> form("#participant-form", person: %{name: name, email: email}) |> render_submit()

  defp dora_id(view) do
    [id] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#participants li[id^=person-]")
      |> Enum.filter(&(LazyHTML.text(&1) =~ "Dora D."))
      |> Enum.map(&(&1 |> LazyHTML.attribute("id") |> hd() |> String.replace("person-", "")))

    String.to_integer(id)
  end

  test "lists the people with their expenses and balance", %{conn: conn, h: h} do
    create!(equal(h, "Essen", 3000, "2026-10-01", h.anna, [h.anna, h.ben, h.cleo]))

    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    assert page_title(view) == "Teilnehmer · Abakus"

    assert texts(view, "#participants > li .list-col-grow > p:first-of-type") ==
             ["Anna das bist du", "Ben", "Cleo"]

    assert texts(view, "#person-#{h.anna} .list-col-grow > p.truncate") ==
             ["1 Ausgabe · Saldo +20,00 €"]

    assert texts(view, "#person-#{h.ben} .list-col-grow > p.truncate") ==
             ["1 Ausgabe · Saldo −10,00 €"]

    assert has_element?(view, "#person-#{h.ben} data[value='-10.00'].text-error-ink")
    refute has_element?(view, "#participants-archived")
    assert has_element?(view, ~s(a[href="/settings/kasse"]), "Gruppe")
  end

  test "adds a person and invites their user, refusing a name taken regardless of case", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    add(view, "  Dora   D. ", " Dora@Example.com")
    assert flash(view, :info) == "„Dora D.“ hinzugefügt und per Mail eingeladen."
    assert_received {:email, %{subject: "Abakus: Einladung", to: [{"", "dora@example.com"}]}}
    assert has_element?(view, "#person_name[phx-patch-focused]:not([value])")
    assert has_element?(view, "#person_email:not([value])")
    assert "Dora D." in texts(view, "#participants li p.font-medium")
    assert last_activity() == "Person „Dora D.“ hinzugefügt"
    assert Participants.get_participant!(dora_id(view)).user_id

    add(view, " dora d. ", "dora2@example.com")
    assert texts(view, "#person_name-error-0") == ["„dora d.“ gibt es schon."]
    assert has_element?(view, "#person_name[value='dora d.']")

    add(view, "", "")
    assert texts(view, "#person_name-error-0") == ["Bitte einen Namen für die Person angeben."]
    assert texts(view, "#person_email-error-0") == ["Bitte eine E-Mail-Adresse angeben."]

    add(view, "Emil", "dora@example.com")
    assert texts(view, "#person_email-error-0") == ["Diese Adresse gehört schon zu einer Person."]
  end

  test "adds a user who signed in before without inviting them", %{conn: conn} do
    Abakus.UsersFixtures.user_fixture(email: "olga@example.com")
    assert_received {:email, %{subject: "Abakus: Anmeldelink"}}
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    add(view, "Olga", "olga@example.com")

    assert flash(view, :info) == "„Olga“ hinzugefügt."
    refute_received {:email, _email}
  end

  test "renames in a popover at the row", %{conn: conn, h: h} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    view |> element("#person-#{h.cleo}-rename") |> render_click()

    assert has_element?(
             view,
             "#rename-#{h.cleo}[data-anchor=person-#{h.cleo}]",
             "„Cleo“ umbenennen"
           )

    assert has_element?(view, "#rename_name[value=Cleo]")

    view |> form("#rename-form", rename: %{name: "ben"}) |> render_submit()
    assert texts(view, "#rename_name-error-0") == ["„ben“ gibt es schon."]

    view |> form("#rename-form", rename: %{name: " Cleopatra "}) |> render_submit()
    assert flash(view, :info) == "Gespeichert."
    refute has_element?(view, "#rename-form")
    assert Participants.get_participant!(h.cleo).name == "Cleopatra"
    assert last_activity() == "Person „Cleo“ umbenannt in „Cleopatra“"
  end

  defp subscribe_to_other_device(participant_id) do
    %{user: user} =
      participant_id |> Participants.get_participant!() |> Abakus.Repo.preload(:user)

    topic = "users_sessions:#{Base.url_encode64(Abakus.Users.generate_user_session_token(user))}"
    AbakusWeb.Endpoint.subscribe(topic)
    topic
  end

  test "archiving oneself leaves the Kasse", %{conn: conn, h: h} do
    topic = subscribe_to_other_device(h.anna)
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    view |> element("#person-#{h.anna}-archive") |> render_click()

    assert {"/", %{"info" => "„Anna“ archiviert."}} = assert_redirect(view)
    assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}
    assert_error_sent 404, fn -> get(conn, ~p"/kasse") end
  end

  test "closing the popover forgets the rename", %{conn: conn, h: h} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    view |> element("#person-#{h.cleo}-rename") |> render_click()
    render_hook(view, "cancel_rename", %{})

    refute has_element?(view, "#rename-form")
  end

  test "archives only a settled person and brings them back", %{conn: conn, h: h} do
    create!(equal(h, "Essen", 3000, "2026-10-01", h.anna, [h.anna, h.ben, h.cleo]))
    dora = person!("Dora")

    {:ok, view, _html} = live(conn, ~p"/settings/kasse/participants")

    view |> element("#person-#{h.ben}-archive") |> render_click()

    assert flash(view, :error) ==
             "Ben hat noch einen Saldo von −10,00 €. Bitte erst ausgleichen, dann archivieren."

    topic = subscribe_to_other_device(dora.id)
    view |> element("#person-#{dora.id}-archive") |> render_click()
    assert flash(view, :info) == "„Dora“ archiviert."
    assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "disconnect"}
    assert texts(view, "#participants-archived") == ["Archiviert 1"]
    assert texts(view, "#participants-archived-list li") == ["Dora 0 Ausgaben Zurückholen"]

    view |> element("#person-#{dora.id}-reactivate") |> render_click()
    assert flash(view, :info) == "„Dora“ reaktiviert."
    refute has_element?(view, "#participants-archived")
    assert last_activity() == "Person „Dora“ reaktiviert"
  end
end
