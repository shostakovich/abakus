defmodule AbakusWeb.NotFoundError do
  @moduledoc "A page or a record the user may not see, or that does not exist: 404."
  defexception message: "no such page", plug_status: 404
end
