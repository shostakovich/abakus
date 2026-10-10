defmodule AbakusWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias AbakusWeb.CoreComponents

  defmodule Owner do
    @moduledoc false
    use Ecto.Schema

    schema "owners" do
      has_one :card, AbakusWeb.CoreComponentsTest.Item
      has_many :items, AbakusWeb.CoreComponentsTest.Item
    end
  end

  defmodule Item do
    @moduledoc false
    use Ecto.Schema

    schema "items" do
      belongs_to :owner, AbakusWeb.CoreComponentsTest.Owner
    end
  end

  test "icon/1 uses a symbol of the icon sprite, hidden from screen readers" do
    icon =
      render_component(&CoreComponents.icon/1, name: "budget", class: "app-icon-sm")
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(LazyHTML.query(icon, "svg"), "class") == ["app-icon app-icon-sm"]
    assert LazyHTML.attribute(LazyHTML.query(icon, "svg"), "aria-hidden") == ["true"]
    assert LazyHTML.attribute(LazyHTML.query(icon, "use"), "href") == ["/images/icons.svg#budget"]
  end

  describe "flash_group/1" do
    # felt.css hides [hidden] with !important, so JS.show alone never reveals the alerts.
    for id <- ["client-error", "server-error"] do
      test "#{id} drops the hidden attribute on disconnect and sets it again on connect" do
        alert =
          render_component(&CoreComponents.flash_group/1, flash: %{})
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("##{unquote(id)}")

        assert LazyHTML.attribute(alert, "hidden") == [""]
        # Only for its own kind of error; the other alert stays hidden.
        assert [
                 "remove_attr",
                 %{"attr" => "hidden", "to" => ".phx-#{unquote(id)} ##{unquote(id)}"}
               ] in js_ops(alert, "phx-disconnected")

        assert ["set_attr", %{"attr" => ["hidden", ""]}] in js_ops(alert, "phx-connected")
      end
    end
  end

  describe "translate_error/1" do
    @types %{
      name: :string,
      token: :string,
      tags: {:array, :string},
      amount: :integer,
      terms: :boolean,
      password: :string,
      password_confirmation: :string
    }

    test "translates Ecto's validation messages" do
      cases = [
        {&validate_required(&1, :name), %{}, "muss ausgefüllt werden"},
        {& &1, %{amount: "viel"}, "ist ungültig"},
        {&validate_format(&1, :name, ~r/^\d+$/), %{name: "x"}, "hat ein ungültiges Format"},
        {&validate_inclusion(&1, :name, ["a"]), %{name: "b"}, "ist kein gültiger Wert"},
        {&validate_exclusion(&1, :name, ["a"]), %{name: "a"}, "ist nicht erlaubt"},
        {&validate_subset(&1, :tags, ["a"]), %{tags: ["b"]}, "enthält einen ungültigen Eintrag"},
        {&validate_acceptance(&1, :terms), %{terms: false}, "muss akzeptiert werden"},
        {&validate_confirmation(&1, :password), %{password: "a", password_confirmation: "b"},
         "stimmt nicht überein"},
        {&validate_length(&1, :name, min: 3), %{name: "ab"},
         "muss mindestens 3 Zeichen lang sein"},
        {&validate_length(&1, :name, max: 1), %{name: "ab"},
         "darf höchstens 1 Zeichen lang sein"},
        {&validate_length(&1, :name, is: 3), %{name: "ab"}, "muss genau 3 Zeichen lang sein"},
        {&validate_length(&1, :token, min: 3, count: :bytes), %{token: "ab"},
         "muss mindestens 3 Bytes lang sein"},
        {&validate_length(&1, :token, max: 1, count: :bytes), %{token: "ab"},
         "darf höchstens 1 Byte lang sein"},
        {&validate_length(&1, :token, is: 4, count: :bytes), %{token: "ab"},
         "muss genau 4 Bytes lang sein"},
        {&validate_length(&1, :tags, min: 2), %{tags: ["a"]}, "braucht mindestens 2 Einträge"},
        {&validate_length(&1, :tags, min: 1), %{tags: []}, "braucht mindestens 1 Eintrag"},
        {&validate_length(&1, :tags, max: 1), %{tags: ["a", "b"]},
         "darf höchstens 1 Eintrag haben"},
        {&validate_length(&1, :tags, max: 2), %{tags: ["a", "b", "c"]},
         "darf höchstens 2 Einträge haben"},
        {&validate_length(&1, :tags, is: 3), %{tags: ["a"]}, "braucht genau 3 Einträge"},
        {&validate_number(&1, :amount, less_than: 5), %{amount: 5}, "muss kleiner als 5 sein"},
        {&validate_number(&1, :amount, greater_than: 5), %{amount: 5}, "muss größer als 5 sein"},
        {&validate_number(&1, :amount, less_than_or_equal_to: 5), %{amount: 6},
         "darf höchstens 5 sein"},
        {&validate_number(&1, :amount, greater_than_or_equal_to: 5), %{amount: 4},
         "muss mindestens 5 sein"},
        {&validate_number(&1, :amount, equal_to: 5), %{amount: 4}, "muss 5 sein"},
        {&validate_number(&1, :amount, not_equal_to: 5), %{amount: 5}, "darf nicht 5 sein"},
        {&validate_required(&1, :name, message: "fehlt"), %{}, "fehlt"}
      ]

      wrong =
        for {validate, params, german} <- cases,
            changeset = {%{}, @types} |> cast(params, Map.keys(@types)) |> validate.(),
            [{_field, {message, _} = error}] = changeset.errors,
            CoreComponents.translate_error(error) != german,
            do: {message, CoreComponents.translate_error(error), german}

      assert wrong == []
    end

    test "translates Ecto's constraint messages" do
      cases = [
        {%Item{}, &unique_constraint(&1, :id), "ist bereits vergeben"},
        {%Item{}, &check_constraint(&1, :id, name: :positive), "ist ungültig"},
        {%Item{}, &foreign_key_constraint(&1, :owner_id), "existiert nicht"},
        {%Item{}, &assoc_constraint(&1, :owner), "existiert nicht"},
        {%Owner{}, &no_assoc_constraint(&1, :card), "ist noch mit diesem Eintrag verknüpft"},
        {%Owner{}, &no_assoc_constraint(&1, :items), "sind noch mit diesem Eintrag verknüpft"}
      ]

      wrong =
        for {data, constrain, german} <- cases,
            {message, _} = error = constraint_error(data, constrain),
            CoreComponents.translate_error(error) != german,
            do: {message, CoreComponents.translate_error(error), german}

      assert wrong == []
    end

    test "translates unsafe_validate_unique's message" do
      error = {"has already been taken", validation: :unsafe_unique, fields: [:name]}
      assert CoreComponents.translate_error(error) == "ist bereits vergeben"
    end
  end

  defp js_ops(element, attribute) do
    [encoded] = LazyHTML.attribute(element, attribute)
    JSON.decode!(encoded)
  end

  # The error the repo adds when the database reports the constraint (Ecto.Repo.Schema).
  defp constraint_error(data, constrain) do
    [constraint] = data |> change() |> constrain.() |> Map.fetch!(:constraints)

    {constraint.error_message,
     [constraint: constraint.error_type, constraint_name: constraint.constraint]}
  end
end
