defmodule AbakusWeb.Depot.NewSecurityTest do
  use Abakus.DataCase

  import Abakus.Depot.SecuritiesFixtures

  alias Abakus.Users.Scope
  alias AbakusWeb.Depot.NewSecurity

  @scope %Scope{}

  @isin_target ["security", "isin"]
  @name_target ["security", "name"]

  test "looks up a new valid ISIN once, in capitals and without spaces" do
    new_security = NewSecurity.new()

    assert {:ok, _new_security} =
             NewSecurity.change(@scope, new_security, %{"isin" => "IE00BKM4GZ67"}, @isin_target)

    assert {:ok, _new_security} =
             NewSecurity.change(@scope, new_security, %{"isin" => "IE00BKM4GZ66"}, @name_target)

    assert {:lookup, searching, "IE00BKM4GZ66"} =
             NewSecurity.change(@scope, new_security, %{"isin" => "ie00 bkm4 gz66"}, @isin_target)

    assert NewSecurity.lookup_text(searching) == "Suche bei Yahoo …"

    assert {:ok, _same} =
             NewSecurity.change(@scope, searching, %{"isin" => "IE00BKM4GZ66"}, @isin_target)
  end

  test "fills in what Yahoo found, unless the ISIN changed meanwhile" do
    {:lookup, searching, isin} =
      NewSecurity.change(@scope, NewSecurity.new(), %{"isin" => "IE00BKM4GZ66"}, @isin_target)

    found =
      NewSecurity.looked_up(searching, {:ok, {isin, {:ok, %{name: "EM IMI", symbol: "IS3N.DE"}}}})

    assert %{"name" => "EM IMI", "symbol" => "IS3N.DE"} = found.form.params
    assert NewSecurity.lookup_text(found) == "Von Yahoo übernommen, bitte prüfen."

    assert NewSecurity.looked_up(searching, {:ok, {"IE00B3RBWM25", {:ok, %{}}}}) == searching
  end

  test "says why the lookup failed" do
    {:lookup, searching, isin} =
      NewSecurity.change(@scope, NewSecurity.new(), %{"isin" => "IE00BKM4GZ66"}, @isin_target)

    assert searching
           |> NewSecurity.looked_up({:ok, {isin, {:error, :not_found}}})
           |> NewSecurity.lookup_text() == "Yahoo kennt diese ISIN nicht."

    assert searching
           |> NewSecurity.looked_up({:exit, :killed})
           |> NewSecurity.lookup_text() == "Yahoo ist nicht erreichbar."
  end

  test "an ISIN a security has is not looked up, that security is named" do
    security = security_fixture(isin: "IE00B3RBWM25")

    assert {:ok, existing} =
             NewSecurity.change(
               @scope,
               NewSecurity.new(),
               %{"isin" => "ie00b3rbwm25"},
               @isin_target
             )

    assert existing.existing == security
    assert NewSecurity.lookup_text(existing) == "Gibt es schon: Vanguard FTSE All-World."
    assert existing.form.errors == []
  end

  test "holds the ISIN's error until 12 characters are typed or the field is left" do
    {:ok, typing} =
      NewSecurity.change(@scope, NewSecurity.new(), %{"isin" => "IE00BKM4GZ6"}, @isin_target)

    refute Keyword.has_key?(typing.form.errors, :isin)

    assert {"ist keine gültige ISIN.", _opts} = NewSecurity.leave_isin(typing).form.errors[:isin]

    {:ok, full} =
      NewSecurity.change(@scope, NewSecurity.new(), %{"isin" => "IE00BKM4GZ67"}, @isin_target)

    assert {"ist keine gültige ISIN.", _opts} = full.form.errors[:isin]
  end

  test "explains the lookup until an ISIN is typed" do
    assert NewSecurity.lookup_text(NewSecurity.new()) ==
             "Name und Symbol kommen aus Yahoos Suche."

    assert NewSecurity.lookup_text(NewSecurity.new(%{"isin" => "IE00"})) == nil
  end
end
