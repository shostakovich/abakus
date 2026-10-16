defmodule Abakus.Kasse.Access do
  @moduledoc """
  Who may call the Kasse (ADR 0019): a person of the Kasse not archived, or the system. Any such person may write any
  entry; any other scope, such as a signed-in user who is not a person, raises `Abakus.Kasse.AccessError`.
  """

  alias Abakus.Kasse.AccessError
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Users.Scope

  @doc "The scope, if it may call the Kasse."
  def check!(%Scope{system: true} = scope), do: scope
  def check!(%Scope{participant: %Participant{archived_at: nil}} = scope), do: scope
  def check!(_scope), do: raise(AccessError)

  @doc "The scope, if it is the system's: for what only jobs may do, such as syncing everybody."
  def system!(%Scope{system: true} = scope), do: scope
  def system!(_scope), do: raise(AccessError)

  @doc "The id of the person acting, for the activity log; nil for the system."
  def actor_id!(%Scope{system: true}), do: nil
  def actor_id!(scope), do: person!(scope).id

  @doc "The scope's person, for reads from their side; the system has none."
  def person!(%Scope{system: false, participant: %Participant{archived_at: nil} = participant}),
    do: participant

  def person!(_scope), do: raise(AccessError)
end
