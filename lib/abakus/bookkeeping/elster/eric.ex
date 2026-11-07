defmodule Abakus.Bookkeeping.Elster.Eric do
  @moduledoc """
  ELSTER through ERiC (ADR 0035): the helper `priv/elster`, built from `c_src/elster.c`, runs as a port and loads
  ERiC from `ERIC_HOME`, a directory mounted into the container, so that neither the repository nor the image
  contains ERiC. Each return gets its own helper and a private temporary directory for the certificate, ERiC's log
  and the protocol, removed afterwards; the PIN reaches the helper only through the port. Outside the image the
  helper is built with `cc -O2 -o priv/elster c_src/elster.c -ldl`.
  """

  @behaviour Abakus.Bookkeeping.Elster

  @timeout :timer.minutes(3)

  @impl true
  def available?, do: home() != nil and File.exists?(helper())

  @impl true
  def submit(submission) do
    if available?(),
      do: Abakus.TmpDir.run("abakus-elster", &run(&1, submission)),
      else: {:error, "ERiC ist nicht eingerichtet."}
  end

  defp run(dir, submission) do
    certificate = Path.join(dir, "certificate.pfx")
    protocol = Path.join(dir, "protocol.pdf")
    File.write!(certificate, submission.certificate)
    File.chmod!(certificate, 0o600)
    {port, os_pid} = open(dir)

    try do
      with {:ok, [elster_tax_number]} <-
             request(port, os_pid, ["stnr", submission.tax_number, submission.state_number]),
           {:ok, [answer]} <-
             request(port, os_pid, [
               "send",
               submission.xml.(elster_tax_number),
               submission.datenart_version,
               certificate,
               submission.pin.(),
               protocol
             ]) do
        {:ok, %{transfer_ticket: transfer_ticket(answer), protocol: read(protocol)}}
      else
        {:error, [message | answers]} -> {:error, message(message, answers)}
        {:error, message} -> {:error, message}
      end
    after
      close(port)
    end
  end

  defp open(dir) do
    port =
      Port.open({:spawn_executable, helper()}, [
        :binary,
        :exit_status,
        {:packet, 4},
        args: [home(), dir],
        env: [{~c"LD_LIBRARY_PATH", String.to_charlist(Path.join(home(), "lib"))}]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {port, os_pid}
  end

  defp request(port, os_pid, fields) do
    send(port, {self(), {:command, encode(fields)}})

    receive do
      {^port, {:data, data}} ->
        case decode(data) do
          ["ok" | values] -> {:ok, values}
          ["error" | values] -> {:error, values}
        end

      {^port, {:exit_status, status}} ->
        {:error, "ERiC ist abgestürzt (Status #{status})."}
    after
      timeout() ->
        # The shell's builtin kill, as the image has no kill binary.
        System.cmd("/bin/sh", ["-c", ~s(kill -9 "$1"), "sh", Integer.to_string(os_pid)])
        {:error, "ERiC hat nicht rechtzeitig geantwortet."}
    end
  end

  defp close(port) do
    try do
      Port.close(port)
    rescue
      # A killed or crashed helper may close the port before us.
      ArgumentError -> :ok
    end

    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      0 -> :ok
    end
  end

  @doc false
  def encode(fields),
    do: for(field <- fields, into: <<>>, do: <<byte_size(field)::32, field::binary>>)

  @doc false
  def decode(<<>>), do: []
  def decode(<<size::32, field::binary-size(size), rest::binary>>), do: [field | decode(rest)]

  defp message(message, answers) do
    details =
      answers
      |> Enum.flat_map(&Regex.scan(~r/<(?:\w+:)?(?:Text|Meldung)>\s*([^<]*?)\s*<\//u, &1))
      |> Enum.map(fn [_element, text] -> text end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Enum.join([message | details], " · ")
  end

  defp transfer_ticket(answer) do
    case Regex.run(~r/<(?:\w+:)?TransferTicket>\s*([^<]*?)\s*<\//, answer) do
      [_element, ticket] when ticket != "" -> ticket
      _none -> nil
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, pdf} when pdf != "" -> pdf
      _none -> nil
    end
  end

  defp timeout, do: config()[:timeout] || @timeout

  defp home, do: config()[:home]

  defp helper, do: config()[:helper] || Application.app_dir(:abakus, "priv/elster")

  defp config, do: Application.get_env(:abakus, __MODULE__, [])
end
