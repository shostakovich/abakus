defmodule Abakus.TmpDir do
  @moduledoc """
  A private temporary directory while a function runs: new, with a random name after `prefix`, only the app may
  enter it, and it is removed afterwards.
  """

  def run(prefix, fun) do
    name = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{name}")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end
end
