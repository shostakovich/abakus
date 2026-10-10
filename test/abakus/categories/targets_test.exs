defmodule Abakus.Categories.TargetsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Categories
  alias Abakus.Categories.{Category, TargetSnooze, TargetVersion}

  setup do
    %{category: category_fixture()}
  end

  defp monthly(from_month, amount, attrs \\ %{}),
    do: Enum.into(attrs, %{from_month: from_month, cadence: :monthly, amount: amount})

  describe "set_target/2" do
    test "stores a monthly target, set aside by default", %{category: category} do
      assert {:ok, version} = Categories.set_target(category, monthly(~D[2026-10-01], 5_000))

      assert %TargetVersion{cadence: :monthly, amount: 5_000, due_on: nil, set_aside: true} =
               version
    end

    test "stores a refill target by a date, not repeating by default", %{category: category} do
      attrs = %{
        from_month: ~D[2026-10-01],
        cadence: "by_date",
        amount: 60_000,
        due_on: ~D[2027-03-31],
        set_aside: false
      }

      assert {:ok,
              %TargetVersion{
                cadence: :by_date,
                due_on: ~D[2027-03-31],
                repeats_yearly: false,
                set_aside: false
              }} = Categories.set_target(category, attrs)

      assert {:ok, %TargetVersion{repeats_yearly: true}} =
               Categories.set_target(category, Map.put(attrs, :repeats_yearly, "true"))
    end

    test "any day stands for its month", %{category: category} do
      assert {:ok, %TargetVersion{id: id, from_month: ~D[2026-10-01]}} =
               Categories.set_target(category, monthly(~D[2026-10-02], 1))

      assert {:ok, %TargetVersion{id: ^id, amount: 2}} =
               Categories.set_target(category, %{
                 "from_month" => "2026-10-20",
                 "cadence" => "monthly",
                 "amount" => "2"
               })

      assert Categories.target_for(category, ~D[2026-10-31]).id == id
    end

    test "stores the first of the month", %{category: category} do
      changeset =
        TargetVersion.changeset(
          %TargetVersion{category_id: category.id},
          monthly("2026-10-02", 1)
        )

      assert get_change(changeset, :from_month) == ~D[2026-10-01]
    end

    test "takes amounts up to 100 billion euros", %{category: category} do
      assert {:ok, _} =
               Categories.set_target(category, monthly(~D[2026-10-01], 10_000_000_000_000))

      for amount <- [10_000_000_000_001, 2 ** 70] do
        assert {:error, changeset} =
                 Categories.set_target(category, monthly(~D[2026-11-01], amount))

        assert %{amount: [message]} = errors_on(changeset)
        assert message =~ "100.000.000.000"
      end
    end

    test "needs a cadence", %{category: category} do
      assert {:error, changeset} =
               Categories.set_target(category, %{from_month: ~D[2026-10-01], cadence: :weekly})

      assert %{cadence: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.set_target(category, %{set_aside: nil, repeats_yearly: nil})

      assert %{
               from_month: ["can't be blank"],
               cadence: ["can't be blank"],
               set_aside: ["can't be blank"],
               repeats_yearly: ["can't be blank"]
             } =
               errors_on(changeset)
    end

    test "a monthly target needs a positive amount and no due date", %{category: category} do
      assert {:error, changeset} = Categories.set_target(category, monthly(~D[2026-10-01], nil))
      assert %{amount: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} = Categories.set_target(category, monthly(~D[2026-10-01], 0))
      assert %{amount: ["must be greater than 0"]} = errors_on(changeset)

      assert {:error, changeset} = Categories.set_target(category, monthly(~D[2026-10-01], 1.5))
      assert %{amount: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.set_target(
                 category,
                 monthly(~D[2026-10-01], 100, due_on: ~D[2026-12-01])
               )

      assert %{due_on: ["muss bei diesem Rhythmus leer sein"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.set_target(
                 category,
                 monthly(~D[2026-10-01], 100, repeats_yearly: true)
               )

      assert %{repeats_yearly: ["gibt es nur bei einem Ziel bis zu einem Datum"]} =
               errors_on(changeset)
    end

    test "a target by a date needs a due date from its first month on", %{category: category} do
      by_date = %{from_month: ~D[2026-10-01], cadence: :by_date, amount: 100}

      assert {:error, changeset} = Categories.set_target(category, by_date)
      assert %{due_on: ["can't be blank"]} = errors_on(changeset)

      for repeats_yearly <- [false, true] do
        attrs = Map.merge(by_date, %{due_on: ~D[2026-09-30], repeats_yearly: repeats_yearly})
        assert {:error, changeset} = Categories.set_target(category, attrs)
        assert %{due_on: ["darf nicht vor dem Beginn des Ziels liegen"]} = errors_on(changeset)
      end

      assert {:ok, _} =
               Categories.set_target(category, Map.put(by_date, :due_on, ~D[2026-10-01]))

      assert {:error, changeset} = Categories.set_target(category, Map.delete(by_date, :amount))
      assert %{amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "cadence none needs neither amount nor due date", %{category: category} do
      assert {:ok, %TargetVersion{cadence: :none, amount: nil}} =
               Categories.set_target(category, %{from_month: ~D[2026-10-01], cadence: :none})

      assert {:error, changeset} =
               Categories.set_target(category, %{
                 from_month: ~D[2026-11-01],
                 cadence: :none,
                 amount: 100,
                 due_on: ~D[2027-01-01]
               })

      assert %{
               amount: ["muss bei diesem Rhythmus leer sein"],
               due_on: ["muss bei diesem Rhythmus leer sein"]
             } =
               errors_on(changeset)
    end

    test "replaces the version of the same month", %{category: category} do
      {:ok, %TargetVersion{id: id}} =
        Categories.set_target(category, monthly(~D[2026-10-01], 5_000))

      assert {:ok, %TargetVersion{id: ^id, amount: 7_000, set_aside: false}} =
               Categories.set_target(category, monthly(~D[2026-10-01], 7_000, set_aside: false))

      assert {:ok, %TargetVersion{id: ^id, cadence: :by_date, repeats_yearly: true}} =
               Categories.set_target(category, %{
                 from_month: ~D[2026-10-01],
                 cadence: :by_date,
                 amount: 7_000,
                 due_on: ~D[2027-01-15],
                 repeats_yearly: true
               })

      assert Repo.aggregate(TargetVersion, :count) == 1
    end

    test "the database keeps amounts positive", %{category: category} do
      version = %TargetVersion{
        category_id: category.id,
        from_month: ~D[2026-10-01],
        cadence: :monthly,
        amount: 0
      }

      assert_raise Ecto.ConstraintError, ~r/target_versions_amount_positive/, fn ->
        Repo.insert(version)
      end
    end

    test "one version per category and month", %{category: category} do
      changeset =
        TargetVersion.changeset(
          %TargetVersion{category_id: category.id},
          monthly(~D[2026-10-01], 1)
        )

      assert {:ok, _} = Repo.insert(changeset)
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{category_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "needs an existing category" do
      assert {:error, changeset} =
               Categories.set_target(%Category{id: -1}, monthly(~D[2026-10-01], 1))

      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end

    test "refuses internal categories" do
      assert {:error, changeset} =
               Categories.set_target(Categories.ready_to_assign!(), monthly(~D[2026-10-01], 1))

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
    end
  end

  describe "target_for/2" do
    test "is the latest version up to the month, ended by cadence none", %{category: category} do
      {:ok, _} = Categories.set_target(category, monthly(~D[2026-03-01], 5_000))
      {:ok, _} = Categories.set_target(category, monthly(~D[2026-06-01], 8_000))
      {:ok, _} = Categories.set_target(category, %{from_month: ~D[2026-09-01], cadence: :none})
      {:ok, _} = Categories.set_target(category, monthly(~D[2027-01-01], 9_000))

      amount_in = fn month ->
        case Categories.target_for(category, month) do
          %TargetVersion{amount: amount} -> amount
          nil -> nil
        end
      end

      months = [~D[2026-02-01], ~D[2026-03-01], ~D[2026-05-15], ~D[2026-06-01], ~D[2026-08-01]]
      months = months ++ [~D[2026-09-01], ~D[2026-12-01], ~D[2027-01-01], ~D[2030-01-01]]
      amounts = Enum.map(months, amount_in)

      assert amounts == [nil, 5_000, 5_000, 8_000, 8_000, nil, nil, 9_000, 9_000]
    end

    test "takes any day or ISO date of the month", %{category: category} do
      {:ok, %TargetVersion{id: id}} = Categories.set_target(category, monthly("2026-10-01", 100))

      assert Categories.target_for(category, "2026-10-31").id == id
      assert Categories.target_for(category, ~D[2026-10-15]).id == id
      assert Categories.target_for(category, "2026-09-30") == nil
    end

    test "only looks at the category's own versions", %{category: category} do
      {:ok, _} = Categories.set_target(category_fixture(), monthly(~D[2026-01-01], 100))
      assert Categories.target_for(category, ~D[2026-10-01]) == nil
    end
  end

  describe "snoozing" do
    test "is per category and month", %{category: category} do
      other = category_fixture()

      assert {:ok, %TargetSnooze{id: id}} = Categories.snooze_target(category, ~D[2026-10-01])
      assert {:ok, %TargetSnooze{id: ^id}} = Categories.snooze_target(category, ~D[2026-10-12])
      assert Repo.aggregate(TargetSnooze, :count) == 1

      assert Categories.target_snoozed?(category, ~D[2026-10-01])
      assert Categories.target_snoozed?(category, ~D[2026-10-20])
      refute Categories.target_snoozed?(category, ~D[2026-11-01])
      refute Categories.target_snoozed?(other, ~D[2026-10-01])

      assert :ok = Categories.unsnooze_target(category, ~D[2026-10-01])
      refute Categories.target_snoozed?(category, ~D[2026-10-01])
    end

    test "any day stands for its month", %{category: category} do
      assert {:ok, %TargetSnooze{month: ~D[2026-10-01]}} =
               Categories.snooze_target(category, ~D[2026-10-09])

      assert Categories.target_snoozed?(category, ~D[2026-10-31])
      assert Categories.target_snoozed?(category, "2026-10-31")
      assert :ok = Categories.unsnooze_target(category, "2026-10-15")
      refute Categories.target_snoozed?(category, ~D[2026-10-01])

      assert {:error, changeset} = Categories.snooze_target(%Category{id: -1}, ~D[2026-10-01])
      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end

    test "one snooze per category and month", %{category: category} do
      changeset =
        TargetSnooze.changeset(%TargetSnooze{category_id: category.id}, %{month: ~D[2026-10-01]})

      assert {:ok, _} = Repo.insert(changeset)
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{category_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "refuses internal categories" do
      assert {:error, changeset} =
               Categories.snooze_target(Categories.ready_to_assign!(), ~D[2026-10-01])

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
    end
  end
end
