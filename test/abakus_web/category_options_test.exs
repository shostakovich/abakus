defmodule AbakusWeb.CategoryOptionsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Categories
  alias AbakusWeb.CategoryOptions

  test "Ready to Assign first, then the visible categories by group with what they have available" do
    group = category_group_fixture(name: "🏠 Wohnen")
    rent = category_fixture(name: "🏡 Miete", category_group_id: group.id)
    old = category_fixture(name: "Alt", category_group_id: group.id, hidden: true)
    {:ok, _} = Categories.assign(rent, ~D[2026-10-01], 95_000)
    giro = account_fixture()

    transaction_fixture(
      account_id: giro.id,
      amount: 200_000,
      category_id: Categories.ready_to_assign!().id
    )

    assert [income, %{name: "🏠 Wohnen", options: [miete]}] = CategoryOptions.build(~D[2026-10-09])

    assert %{name: "Einnahme", options: [%{name: "Zu verteilen", available: 105_000}]} = income

    assert %{name: "🏡 Miete", text: "Wohnen: 🏡 Miete", key: "miete", available: 95_000} = miete
    assert miete.id == rent.id

    # A hidden category shows where a transaction keeps it.
    assert [_income, %{options: [_miete, kept]}] = CategoryOptions.build(~D[2026-10-09], [old.id])
    assert kept.id == old.id
    assert CategoryOptions.find(CategoryOptions.build(~D[2026-10-09]), old.id) == nil
  end
end
