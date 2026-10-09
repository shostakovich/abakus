defmodule Abakus.Users.Scope do
  @moduledoc "The caller of a context function: which user is signed in."

  alias Abakus.Users.User

  defstruct user: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
