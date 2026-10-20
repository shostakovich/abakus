defmodule Abakus.BankSync.AccessError do
  @moduledoc "A caller of bank sync who does not own the budget: 404, like a page they may not see."
  defexception message: "bank sync is the budget owner's", plug_status: 404
end
