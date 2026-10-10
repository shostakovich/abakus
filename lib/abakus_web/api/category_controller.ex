defmodule AbakusWeb.Api.CategoryController do
  @moduledoc "The plan's category groups and categories, the internal ones with Ready to Assign first, as in YNAB."

  use AbakusWeb, :controller

  alias Abakus.Categories
  alias AbakusWeb.Api.YnabJSON

  def index(conn, _params) do
    groups = Categories.list_category_groups(internal: true)

    json(conn, %{
      data: %{category_groups: Enum.map(groups, &YnabJSON.category_group/1), server_knowledge: 0}
    })
  end
end
