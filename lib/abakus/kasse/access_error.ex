defmodule Abakus.Kasse.AccessError do
  @moduledoc "A caller of the Kasse who is not a person of it: 404, like a page they may not see."
  defexception message: "not a person of the Kasse", plug_status: 404
end
