defmodule Abakus.Users.Scope do
  @moduledoc "The caller of a context function: which user is signed in, and which person of the Kasse they are."

  alias Abakus.Kasse.Participants
  alias Abakus.Users.User

  defstruct user: nil, participant: nil

  def for_user(user, participant \\ nil)
  def for_user(%User{} = user, participant), do: %__MODULE__{user: user, participant: participant}
  def for_user(nil, _participant), do: nil

  @doc "The scope of a signed-in user with the active person of the Kasse they are, if any."
  def load(%User{} = user), do: for_user(user, Participants.for_user(user))
  def load(nil), do: nil
end
