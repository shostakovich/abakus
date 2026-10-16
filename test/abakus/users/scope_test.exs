defmodule Abakus.Users.ScopeTest do
  use ExUnit.Case, async: true

  alias Abakus.Users.{Scope, User}

  describe "system/0" do
    test "is a scope without a user or a person, marked as the system's" do
      assert %Scope{user: nil, participant: nil, system: true} = Scope.system()
    end

    test "differs from an empty scope" do
      refute Scope.system() == %Scope{}
    end
  end

  describe "budget_owner?/1" do
    test "is true for the budget owner's scope" do
      assert Scope.budget_owner?(Scope.for_user(%User{budget_owner: true}))
    end

    test "is false for another user's scope" do
      refute Scope.budget_owner?(Scope.for_user(%User{budget_owner: false}))
    end

    test "is false for the system scope" do
      refute Scope.budget_owner?(Scope.system())
    end
  end
end
