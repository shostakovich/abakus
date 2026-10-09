defmodule AbakusWeb.ErrorHTML do
  @moduledoc false
  use AbakusWeb, :html

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
