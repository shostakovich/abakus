defmodule AbakusWeb.BudgetLive do
  use AbakusWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Budget</.header>
      <.card>
        <p class="mb-0">Hier entsteht das Budget. Es kommt mit den nächsten Schritten.</p>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Budget")}
end
