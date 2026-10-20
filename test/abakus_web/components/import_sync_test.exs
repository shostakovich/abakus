defmodule AbakusWeb.ImportSyncTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.ImportSync

  test "writes the counts of an import with Abakus.Format" do
    assert ImportSync.new_label(1234) == "1.234 neu"
    assert ImportSync.matched_label(1) == "1 Zuordnungsvorschlag"
    assert ImportSync.matched_label(1234) == "1.234 Zuordnungsvorschläge"
  end
end
