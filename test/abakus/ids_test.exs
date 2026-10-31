defmodule Abakus.IdsTest do
  use ExUnit.Case, async: true

  alias Abakus.Ids

  @category "01890a5d-ac96-774b-bcce-b302099a8057"

  test "names rows with a natural key as sync/PROTOCOL.md lists them" do
    assert Ids.assignment(@category, ~D[2026-11-01]) == "6acb0211-c88e-59b4-baca-87f0fe072024"
    assert Ids.target_snooze(@category, ~D[2026-11-01]) == "40ec28ed-8c55-5958-9143-194ff78e701e"
    assert Ids.target_version(@category, ~D[2026-11-01]) == "dbbd70b6-fe59-5ed4-b545-d4b106935aee"
    assert Ids.transfer_payee(@category) == "e884f20e-330e-5cd4-adbd-a7bbed724916"

    assert Ids.entered_transaction(@category, ~D[2026-12-01]) ==
             "28bca64b-3fac-52b1-8dde-6a7a1ce968b0"
  end

  test "a new id is a UUIDv7 later than the one before" do
    [first, second] = [Ids.generate(), Ids.generate()]
    assert <<_::binary-14, "7", _::binary>> = first
    assert first < second
  end

  test "casts a client's id to lowercase and refuses anything else" do
    assert Ids.cast(String.upcase(@category)) == {:ok, @category}
    assert Ids.cast("x") == :error
    assert Ids.cast(42) == :error
    assert Ids.cast(nil) == :error
  end
end
