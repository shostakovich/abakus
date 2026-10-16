defmodule Abakus.Kasse.ActivityTexts do
  @moduledoc "The texts of the activity log, as tests check them."

  alias Abakus.Kasse.Activities
  alias Abakus.Users.Scope

  @doc "The texts of all entries, newest first; `:oldest_first` turns them round."
  def activity_texts(order \\ :newest_first) do
    texts = Enum.map(Activities.list_activities(Scope.system()), & &1.details.text)
    if order == :oldest_first, do: Enum.reverse(texts), else: texts
  end

  @doc "The text of the newest entry."
  def last_activity, do: hd(Activities.list_activities(Scope.system(), limit: 1)).details.text
end
