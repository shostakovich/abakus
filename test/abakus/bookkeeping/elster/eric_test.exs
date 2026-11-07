defmodule Abakus.Bookkeeping.Elster.EricTest do
  # Builds the helper from c_src/elster.c and runs it against a stand-in for ERiC.
  use ExUnit.Case

  alias Abakus.Bookkeeping.Elster.Eric

  @moduletag :cc

  setup_all do
    dir = Path.join(System.tmp_dir!(), "abakus-eric-test-#{System.unique_integer([:positive])}")
    home = Path.join(dir, "eric")
    File.mkdir_p!(Path.join(home, "lib/plugins"))

    library =
      if match?({:unix, :darwin}, :os.type()), do: "libericapi.dylib", else: "libericapi.so"

    helper = Path.join(dir, "elster")

    cc!(["-shared", "-fPIC", "-o", Path.join([home, "lib", library]), fixture("mock_eric.c")])
    cc!(["-O2", "-Wall", "-Wextra", "-Werror", "-o", helper, "c_src/elster.c", "-ldl"])

    on_exit(fn -> File.rm_rf!(dir) end)
    %{home: home, helper: helper, dir: dir}
  end

  setup c do
    use_eric(home: c.home, helper: c.helper)
    :ok
  end

  defp cc!(args) do
    {output, status} = System.cmd("cc", args, stderr_to_stdout: true)
    if status != 0, do: flunk("cc failed: #{output}")
  end

  defp fixture(name), do: Path.expand("../../../fixtures/bookkeeping/#{name}", __DIR__)

  defp use_eric(config) do
    Application.put_env(:abakus, Eric, config)
    on_exit(fn -> Application.delete_env(:abakus, Eric) end)
  end

  defp submission(attrs \\ %{}) do
    Map.merge(
      %{
        tax_number: "30/123/45678",
        state_number: "11",
        xml: fn tax_number -> "<Steuernummer>#{tax_number}</Steuernummer>" end,
        datenart_version: "UStVA_2027",
        certificate: "PKCS12 certificate",
        pin: fn -> "4711" end
      },
      Map.new(attrs)
    )
  end

  defp tmp_dirs, do: Path.wildcard(Path.join(System.tmp_dir!(), "abakus-elster-*"))

  test "writes the tax number in ELSTER's format, sends the return and brings back ticket and protocol" do
    assert Eric.available?()

    assert Eric.submit(submission()) ==
             {:ok,
              %{
                transfer_ticket: "tt-42",
                protocol: "%PDF-mock UStVA_2027 <Steuernummer>1130012345678</Steuernummer>"
              }}

    assert tmp_dirs() == []
  end

  test "gives back ERiC's message with ELSTER's findings" do
    assert Eric.submit(submission(pin: fn -> "0000" end)) ==
             {:error, "ERiC-Fehler 610201101: Fehlertext 610201101"}

    assert Eric.submit(submission(xml: fn _number -> "FEHLER" end)) ==
             {:error, "ERiC-Fehler 610001222: Fehlertext 610001222 · Die Kennzahl 83 fehlt."}

    assert Eric.submit(submission(state_number: "9")) ==
             {:error, "ERiC-Fehler 610001034: Fehlertext 610001034"}

    assert Eric.submit(submission(certificate: "kein Zertifikat")) ==
             {:error, "ERiC-Fehler 610201016: Fehlertext 610201016"}
  end

  test "survives a crash of ERiC" do
    assert {:error, "ERiC ist abgestürzt" <> _status} =
             Eric.submit(submission(xml: fn _number -> "CRASH" end))

    assert tmp_dirs() == []
    assert {:ok, _receipt} = Eric.submit(submission())
  end

  test "kills ERiC when it does not answer in time, also without a kill binary", c do
    use_eric(home: c.home, helper: c.helper, timeout: 1_000)
    path = System.get_env("PATH")
    System.put_env("PATH", "")
    on_exit(fn -> System.put_env("PATH", path) end)
    pid_file = Path.join(c.dir, "hung.pid")

    assert Eric.submit(submission(xml: fn _number -> "HANG #{pid_file}" end)) ==
             {:error, "ERiC hat nicht rechtzeitig geantwortet."}

    assert gone?(File.read!(pid_file))
    assert tmp_dirs() == []
  end

  test "keeps the certificate in a directory only the app can read", c do
    use_eric(home: c.home, helper: c.helper, timeout: 1_000)
    pid_file = Path.join(c.dir, "waiting.pid")

    send =
      Task.async(fn -> Eric.submit(submission(xml: fn _number -> "HANG #{pid_file}" end)) end)

    wait_for(pid_file)

    assert [dir] = tmp_dirs()
    assert mode(dir) == 0o700
    assert mode(Path.join(dir, "certificate.pfx")) == 0o600

    assert Task.await(send) == {:error, "ERiC hat nicht rechtzeitig geantwortet."}
  end

  defp mode(path), do: Bitwise.band(File.stat!(path).mode, 0o777)

  defp wait_for(path, tries \\ 50) do
    cond do
      File.exists?(path) ->
        :ok

      tries == 0 ->
        flunk("#{path} never appeared")

      true ->
        Process.sleep(20)
        wait_for(path, tries - 1)
    end
  end

  defp gone?(os_pid, tries \\ 50)
  defp gone?(_os_pid, 0), do: false

  defp gone?(os_pid, tries) do
    {_output, status} =
      System.cmd("/bin/sh", ["-c", ~s(kill -0 "$1"), "sh", os_pid], stderr_to_stdout: true)

    if status == 0 do
      Process.sleep(20)
      gone?(os_pid, tries - 1)
    else
      true
    end
  end

  test "says when ERiC cannot be loaded or is not set up", c do
    use_eric(home: Path.join(c.dir, "missing"), helper: c.helper)
    assert {:error, "ERiC ließ sich nicht laden: " <> _reason} = Eric.submit(submission())

    use_eric(helper: c.helper)
    refute Eric.available?()
    assert Eric.submit(submission()) == {:error, "ERiC ist nicht eingerichtet."}
  end
end
