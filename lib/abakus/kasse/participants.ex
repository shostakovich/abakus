defmodule Abakus.Kasse.Participants do
  @moduledoc """
  The people of the group, each a user who signs in (ADR 0008). The functions take the caller's scope, which
  `Abakus.Kasse.Access` checks; every change is logged with the scope's person, or none for the system.
  """

  import Ecto.Query

  alias Abakus.Kasse.{Access, Activities, Balances}
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Money
  alias Abakus.Repo
  alias Abakus.Users
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @doc "The people, by name: `:active` (default), `:archived` or `:all`."
  def list_participants(%Scope{} = scope, which \\ :active) do
    Access.check!(scope)

    Participant
    |> archived(which)
    |> order_by([p], [fragment("? COLLATE NOCASE", p.name), p.id])
    |> Repo.all()
  end

  defp archived(query, :active), do: where(query, [p], is_nil(p.archived_at))
  defp archived(query, :archived), do: where(query, [p], not is_nil(p.archived_at))
  defp archived(query, :all), do: query

  @doc "The person with `id`, or nil."
  def get_participant(%Scope{} = scope, id) do
    Access.check!(scope)
    Repo.get(Participant, id)
  end

  @doc "The person with `id`; raises if there is none."
  def get_participant!(%Scope{} = scope, id) do
    Access.check!(scope)
    Repo.get!(Participant, id)
  end

  @doc "The active person a user is, or nil; it builds the scope, so it takes none."
  def for_user(%User{id: user_id}) when is_integer(user_id) do
    Repo.one(from p in Participant, where: p.user_id == ^user_id and is_nil(p.archived_at))
  end

  def for_user(_user), do: nil

  @doc "A changeset for the name form."
  def change_participant(%Participant{} = participant, attrs \\ %{}),
    do: Participant.changeset(participant, attrs)

  @doc "A changeset for the form that adds a person: name and email address."
  def change_new_participant(attrs \\ %{}),
    do: Participant.create_changeset(%Participant{}, attrs)

  @doc """
  Adds a person as the user with their email address, creating that user if there is none; a user who already is a
  person is refused.
  """
  def create_participant(%Scope{} = scope, attrs) do
    actor_id = Access.actor_id!(scope)
    changeset = change_new_participant(attrs)

    Repo.transact(fn ->
      with {:ok, user} <- find_or_create_user(changeset),
           {:ok, participant} <- Repo.insert(Changeset.put_change(changeset, :user_id, user.id)),
           {:ok, _activity} <-
             Activities.log_settings(actor_id, "Person „#{participant.name}“ hinzugefügt") do
        {:ok, %{participant | user: user}}
      end
    end)
  end

  defp find_or_create_user(changeset) do
    email = Changeset.get_field(changeset, :email)

    with nil <- email && Users.get_user_by_email(email),
         {:ok, user} <- create_user(changeset, email) do
      {:ok, user}
    else
      %User{} = user -> {:ok, user}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp create_user(changeset, nil), do: Changeset.apply_action(changeset, :insert)

  defp create_user(changeset, email) do
    case Users.create_user(%{email: email}) do
      {:ok, user} ->
        {:ok, user}

      {:error, user_changeset} ->
        user_changeset.errors
        |> Keyword.get_values(:email)
        |> Enum.reduce(changeset, fn {message, opts}, changeset ->
          Changeset.add_error(changeset, :email, message, opts)
        end)
        |> Changeset.apply_action(:insert)
    end
  end

  @doc """
  Adds a person like `create_participant/2` and mails their user a sign-in link unless they have signed in before.
  `{:error, :mail_not_delivered, participant}`: the person exists, but has to ask for a link on the sign-in page.
  """
  def invite_participant(%Scope{} = scope, attrs, magic_link_url_fun) do
    with {:ok, participant} <- create_participant(scope, attrs) do
      invite(participant, magic_link_url_fun)
    end
  end

  defp invite(%Participant{user: %User{confirmed_at: nil} = user} = participant, url_fun) do
    case Users.deliver_invite(user, url_fun) do
      {:ok, _email} -> {:ok, participant}
      {:error, _reason} -> {:error, :mail_not_delivered, participant}
    end
  end

  defp invite(participant, _url_fun), do: {:ok, participant}

  @doc "Renames a person; logged only when the name changes."
  def rename_participant(%Scope{} = scope, %Participant{} = participant, attrs) do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      with {:ok, renamed} <- Repo.update(Participant.changeset(participant, attrs)),
           {:ok, _activity} <- log_rename(actor_id, participant.name, renamed.name) do
        {:ok, renamed}
      end
    end)
  end

  defp log_rename(_actor_id, same, same), do: {:ok, nil}

  defp log_rename(actor_id, old, new),
    do: Activities.log_settings(actor_id, "Person „#{old}“ umbenannt in „#{new}“")

  @doc """
  Archives a person. Refused while their balance is not 0: they would vanish from the forms while
  money is still owed.
  """
  def archive_participant(%Scope{} = scope, %Participant{} = participant) do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      case Balances.balance_of(participant.id) do
        0 ->
          set_archived(actor_id, participant, DateTime.utc_now(), "archiviert")

        balance ->
          participant
          |> Changeset.change()
          |> Changeset.add_error(
            :archived_at,
            "#{participant.name} hat noch einen Saldo von #{Money.euros(balance)}. " <>
              "Bitte erst ausgleichen, dann archivieren."
          )
          |> Changeset.apply_action(:update)
      end
    end)
  end

  @doc "Brings an archived person back."
  def reactivate_participant(%Scope{} = scope, %Participant{} = participant) do
    actor_id = Access.actor_id!(scope)
    Repo.transact(fn -> set_archived(actor_id, participant, nil, "reaktiviert") end)
  end

  # Logged even when nothing changes.
  defp set_archived(actor_id, participant, archived_at, verb) do
    with {:ok, participant} <-
           participant |> Changeset.change(archived_at: archived_at) |> Repo.update(),
         {:ok, _activity} <-
           Activities.log_settings(actor_id, "Person „#{participant.name}“ #{verb}") do
      {:ok, participant}
    end
  end
end
