defmodule Abakus.Depot.Receipts.Recognition do
  @moduledoc """
  The queue of receipts to recognise, see `Abakus.Depot.Receipts.recognise/1`: one after the
  other in the order they came, so that the model on the user's server (ADR 0015) never gets
  two requests at once.
  """
  use GenServer

  require Logger

  alias Abakus.Depot.Receipts

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Queues the receipt with `id`."
  def enqueue(id), do: GenServer.cast(__MODULE__, {:recognise, id})

  @impl true
  def init(_opts), do: {:ok, nil}

  # A crash would lose the receipts queued behind this one.
  @impl true
  def handle_cast({:recognise, id}, state) do
    Receipts.recognise(id)
    {:noreply, state}
  rescue
    exception ->
      Logger.error("recognising receipt #{id} failed: " <> Exception.message(exception))
      {:noreply, state}
  catch
    :exit, reason ->
      Logger.error("recognising receipt #{id} failed: #{inspect(reason)}")
      {:noreply, state}
  end
end
