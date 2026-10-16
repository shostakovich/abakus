defmodule Mix.Tasks.Abakus.MeasureReceiptsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Abakus.MeasureReceipts

  test "refuses a sample of less than one receipt" do
    assert_raise Mix.Error, "--sample needs at least 1", fn ->
      MeasureReceipts.run(["--sample", "0"])
    end
  end
end
