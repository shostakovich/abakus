defmodule Abakus.TmpDirTest do
  use ExUnit.Case, async: true

  alias Abakus.TmpDir

  test "runs in a new private directory and removes it afterwards" do
    dir =
      TmpDir.run("abakus-test", fn dir ->
        assert Bitwise.band(File.stat!(dir).mode, 0o777) == 0o700
        assert File.ls!(dir) == []
        File.write!(Path.join(dir, "file"), "data")
        dir
      end)

    assert Path.basename(dir) =~ ~r/^abakus-test-[\w-]{22}$/
    refute File.exists?(dir)
  end

  test "removes the directory when the function raises" do
    assert_raise RuntimeError, fn ->
      TmpDir.run("abakus-test", fn dir ->
        send(self(), {:dir, dir})
        raise "failed"
      end)
    end

    assert_received {:dir, dir}
    refute File.exists?(dir)
  end
end
