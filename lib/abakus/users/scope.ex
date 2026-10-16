defmodule Abakus.Users.Scope do
  @moduledoc """
  The caller of a context function (ADR 0019): which user is signed in, which person of the Kasse they are, and
  whether they have portfolios in the Depot; or the system, for callers without a person, such as jobs and tasks.
  """

  alias Abakus.Depot.Portfolios
  alias Abakus.Kasse.Participants
  alias Abakus.Users.User

  defstruct user: nil, participant: nil, depot: false, system: false

  def for_user(user, participant \\ nil)
  def for_user(%User{} = user, participant), do: %__MODULE__{user: user, participant: participant}
  def for_user(nil, _participant), do: nil

  @doc "The scope of a signed-in user with the active person of the Kasse they are, if any, and their Depot."
  def load(%User{} = user),
    do: %{for_user(user, Participants.for_user(user)) | depot: Portfolios.any?(user)}

  def load(nil), do: nil

  @doc "The scope of callers without a person: jobs, release and mix tasks, and MCP reads."
  def system, do: %__MODULE__{system: true}

  @doc "Whether the scope's user owns the budget (ADR 0007); the system does not."
  def budget_owner?(%__MODULE__{user: %User{budget_owner: true}}), do: true
  def budget_owner?(%__MODULE__{}), do: false
end
