defmodule Abakus.Bookkeeping.FakeElster do
  @moduledoc """
  ELSTER in tests. Once `serve/1` started it, it keeps every submission, with its XML and PIN, and answers with a
  transfer ticket and a protocol, or with `error:`; it writes every tax number as `elster_tax_number:`. With
  `crash: true` it raises, with `hold: pid` it tells `pid` `{FakeElster, :holding, sender}` and answers once
  `release/1` let the sender go. Without `serve/1` it refuses to send.
  """
  @behaviour Abakus.Bookkeeping.Elster

  @doc "Starts ELSTER for the test, answering with `error: message` if given."
  def serve(opts \\ []) do
    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start:
        {Agent, :start_link,
         [
           fn ->
             %{
               error: opts[:error],
               crash: opts[:crash],
               hold: opts[:hold],
               elster_tax_number: opts[:elster_tax_number] || "1130012345678",
               submissions: []
             }
           end,
           [name: __MODULE__]
         ]}
    })
  end

  @doc "Lets a held submission get its answer."
  def release(sender), do: send(sender, {__MODULE__, :release})

  @doc """
  Waits for the sends running apart from their page, and for `live_view` to take their results and what its panel
  tells it of them.
  """
  def await_sends(live_view \\ nil) do
    for pid <- Task.Supervisor.children(Abakus.Bookkeeping.TaskSupervisor) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, _pid, _reason} -> :ok
      after
        1_000 -> raise "the send did not finish"
      end
    end

    if live_view, do: for(_round <- 1..2, do: :sys.get_state(live_view))
    :ok
  end

  @doc "The submissions so far, the latest first."
  def submissions, do: Agent.get(__MODULE__, & &1.submissions)

  @impl true
  def available?, do: true

  @impl true
  def submit(submission) do
    if Process.whereis(__MODULE__), do: answer(submission), else: {:error, "ELSTER ist nicht da."}
  end

  defp hold do
    case Agent.get(__MODULE__, & &1) do
      %{crash: true} ->
        raise "ELSTER crashed"

      %{hold: pid} when is_pid(pid) ->
        send(pid, {__MODULE__, :holding, self()})

        receive do
          {__MODULE__, :release} -> :ok
        end

      _state ->
        :ok
    end
  end

  defp answer(submission) do
    hold()

    Agent.get_and_update(__MODULE__, fn state ->
      sent =
        submission
        |> Map.take([:tax_number, :state_number, :datenart_version, :certificate])
        |> Map.merge(%{xml: submission.xml.(state.elster_tax_number), pin: submission.pin.()})

      reply =
        if state.error,
          do: {:error, state.error},
          else:
            {:ok,
             %{
               transfer_ticket: "et-#{length(state.submissions) + 1}",
               protocol: "%PDF-1.4 Protokoll"
             }}

      {reply, %{state | submissions: [sent | state.submissions]}}
    end)
  end
end
