defmodule Abakus.ApplicationTest do
  use ExUnit.Case, async: true

  test "every job child has its own id, so the app starts with the jobs on" do
    ids = Enum.map(Abakus.Application.jobs(true), &Supervisor.child_spec(&1, []).id)

    assert ids == Enum.uniq(ids)
  end
end
