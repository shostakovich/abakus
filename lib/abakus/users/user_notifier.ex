defmodule Abakus.Users.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  require Logger

  alias Abakus.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:abakus, :mail_from))
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} = error ->
        Logger.error("Mail \"#{subject}\" not delivered: #{inspect(reason)}")
        error
    end
  end

  def deliver_invite(user, url) do
    deliver(user.email, "Abakus: Einladung", """
    Hallo,

    du bist zu Abakus eingeladen, unserem Haushaltsbudget. Mit diesem Link meldest du dich an.
    Er gilt 15 Minuten und nur einmal:

    #{url}

    Danach legst du in den Einstellungen einen Passkey an. Ist der Link abgelaufen, schickt dir
    die Anmeldeseite einen neuen.
    """)
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Abakus: neue E-Mail-Adresse bestätigen", """
    Hallo,

    mit diesem Link bestätigst du deine neue E-Mail-Adresse für Abakus:

    #{url}

    Wenn du das nicht angefordert hast, ignoriere diese Mail.
    """)
  end

  def deliver_passkey_added(user, passkey) do
    deliver(user.email, "Abakus: neuer Passkey „#{passkey.name}“", """
    Hallo,

    für deine Anmeldung bei Abakus wurde der Passkey „#{passkey.name}“ angelegt.

    Warst du das nicht, melde dich mit einem Anmeldelink an und lösche ihn in den Einstellungen.
    """)
  end

  def deliver_login_instructions(user, url) do
    deliver(user.email, "Abakus: Anmeldelink", """
    Hallo,

    mit diesem Link meldest du dich bei Abakus an. Er gilt 15 Minuten und nur einmal:

    #{url}

    Danach kannst du in den Einstellungen einen Passkey anlegen.

    Wenn du das nicht angefordert hast, ignoriere diese Mail.
    """)
  end
end
