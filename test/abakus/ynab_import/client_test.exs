defmodule Abakus.YnabImport.ClientTest do
  use ExUnit.Case

  alias Abakus.FakeYnab
  alias Abakus.YnabImport.Client

  setup do
    FakeYnab.start(%{"plan-1" => %{"id" => "plan-1", "name" => "Haushalt"}})
    :ok
  end

  test "plans/1 lists the plans the token sees" do
    assert {:ok, [%{"id" => "plan-1", "name" => "Haushalt"}]} = Client.plans(FakeYnab.token())
  end

  test "plan/2 fetches a plan's export" do
    assert Client.plan(FakeYnab.token(), "plan-1") ==
             {:ok, %{"id" => "plan-1", "name" => "Haushalt"}}
  end

  test "an error answer gives YNAB's status and detail" do
    assert Client.plan(FakeYnab.token(), "other") == {:error, {:ynab, 404, "Resource not found"}}
    assert Client.plans("wrong") == {:error, {:ynab, 401, "Unauthorized"}}
  end

  test "an unreachable YNAB gives the reason" do
    Application.put_env(:abakus, Client, base_url: "http://127.0.0.1:1/v1")
    assert {:error, {:ynab, {:failed_connect, _details}}} = Client.plans(FakeYnab.token())
  end
end
