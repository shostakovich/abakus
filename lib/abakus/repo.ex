defmodule Abakus.Repo do
  use Ecto.Repo,
    otp_app: :abakus,
    adapter: Ecto.Adapters.SQLite3

  @after_commit {__MODULE__, :after_commit}

  defoverridable transact: 2

  @doc "`Ecto.Repo.transact/2`; the outermost one also runs what `after_commit/2` deferred, once it has committed."
  def transact(fun_or_multi, opts) do
    if in_transaction?() do
      super(fun_or_multi, opts)
    else
      try do
        result = super(fun_or_multi, opts)
        if match?({:ok, _result}, result), do: run_after_commit()
        result
      after
        Process.delete(@after_commit)
      end
    end
  end

  @doc """
  Runs `fun` once the current transaction has committed, at once outside one, and never when it rolls back. Of the
  functions deferred under one `key` within a transaction only the first runs.
  """
  def after_commit(key, fun) when is_function(fun, 0) do
    if in_transaction?() do
      Process.put(@after_commit, Map.put_new(Process.get(@after_commit, %{}), key, fun))
      :ok
    else
      fun.()
      :ok
    end
  end

  defp run_after_commit do
    deferred = Process.delete(@after_commit) || %{}
    Enum.each(deferred, fn {_key, fun} -> fun.() end)
  end
end
