defmodule Abakus.Depot.Receipts.Pdftotext do
  @moduledoc """
  The text of a PDF from poppler's `pdftotext`, in its layout, as the image installs it. A PDF
  that keeps it busy longer than 30 seconds has no text, so that it does not hold up the queue.
  """
  @behaviour Abakus.Depot.Receipts.TextExtractor

  require Logger

  @timeout 30_000

  @impl true
  def text(path) do
    case System.find_executable("pdftotext") do
      nil ->
        Logger.warning("pdftotext is missing, receipts are not recognised")
        :error

      pdftotext ->
        run(pdftotext, path)
    end
  end

  defp run(pdftotext, path) do
    port =
      Port.open({:spawn_executable, pdftotext}, [
        :binary,
        :exit_status,
        args: ["-q", "-layout", "-enc", "UTF-8", path, "-"]
      ])

    case collect(port, [], System.monotonic_time(:millisecond) + @timeout) do
      {:ok, text} -> if String.trim(text) == "", do: :error, else: {:ok, text}
      :error -> :error
    end
  end

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, data}} -> collect(port, [output | data], deadline)
      {^port, {:exit_status, 0}} -> {:ok, IO.iodata_to_binary(output)}
      {^port, {:exit_status, _status}} -> :error
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Logger.warning("pdftotext took longer than #{div(@timeout, 1000)} seconds")
        kill(port)
        :error
    end
  end

  defp kill(port) do
    with {:os_pid, os_pid} <- Port.info(port, :os_pid) do
      System.cmd("kill", ["-KILL", to_string(os_pid)])
    end

    Port.close(port)
    flush(port)
  catch
    :error, :badarg -> flush(port)
  end

  defp flush(port) do
    receive do
      {^port, _message} -> flush(port)
    after
      0 -> :ok
    end
  end
end
