defmodule Abakus.Bookkeeping.CategoryTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.Category

  test "lists the 38 Lexoffice categories and the §13b variants, one to one" do
    categories = Category.all()

    assert length(categories) == 46
    assert length(Enum.filter(categories, &Category.reverse_charge?/1)) == 8
    assert categories |> Enum.map(& &1.lexoffice_id) |> Enum.uniq() |> length() == 46
    assert categories |> Enum.map(& &1.key) |> Enum.uniq() |> length() == 46
  end

  test "maps a category to its EÜR line and, under §13b, its Kennzahl of the VAT return" do
    assert %Category{name: "Internet", euer: 280, vat: :rate_19, vat_return: nil} =
             Category.get("internet")

    assert %Category{name: "Lizenzen und Konzessionen §13b", euer: 183, vat_return: 46} =
             Category.get("licenses_13b_eu")

    assert %Category{name: "Lizenzen und Konzessionen §13b Drittland", vat_return: 84} =
             Category.get("licenses_13b_third_country")

    assert %Category{euer: nil} = Category.get("private")
    assert Category.get("unknown") == nil
  end

  test "reverse charge fits the §13b categories and only them" do
    assert Category.fits?(Category.get("licenses_13b_eu"), :reverse_charge)
    refute Category.fits?(Category.get("licenses_13b_eu"), :rate_19)
    refute Category.fits?(Category.get("licenses"), :reverse_charge)
    assert Category.fits?(Category.get("licenses"), :rate_0)
  end

  test "groups the categories by their Lexoffice group, each once" do
    groups = Enum.map(Category.grouped(), &elem(&1, 0))

    assert hd(groups) == "Einnahmen"
    assert groups == Enum.uniq(groups)
  end
end
