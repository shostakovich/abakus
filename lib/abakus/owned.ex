defmodule Abakus.Owned do
  @moduledoc """
  The budget's rows belong to a user (ADR 0019): the scope's user id, a query narrowed to their rows, and a record
  that is theirs; another user's behaves like a missing one.
  """

  import Ecto.Query

  alias Abakus.Users.{Scope, User}

  def user_id(%Scope{user: %User{id: id}}), do: id

  def owned(queryable, scope), do: where(queryable, [r], r.user_id == ^user_id(scope))

  def own!(scope, %schema{user_id: user_id} = record) do
    if user_id == user_id(scope), do: record, else: raise(Ecto.NoResultsError, queryable: schema)
  end
end
