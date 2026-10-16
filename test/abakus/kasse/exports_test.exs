defmodule Abakus.Kasse.ExportsTest do
  use Abakus.DataCase

  import Abakus.KasseFixtures

  alias Abakus.Kasse.{Categories, Expenses, Exports, Participants, Settings}
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Users.Scope

  @now ~U[2026-10-03 10:00:00Z]
  @opts [now: @now, today: ~D[2026-10-03]]
  @header "ID;Datum;Titel;Kategorie;Bezahlt von;Betrag (EUR);Originalbetrag;Währung;Kurs;Art;Aufteilung;Notiz"
  @long_title "Sehr langer Titel mit <Sonderzeichen> & mehr Text dahinter"

  for {text, cell} <- [
        {"=SUM(A1)", "'=SUM(A1)"},
        {"+49 Telefon", "'+49 Telefon"},
        {"-Rabatt", "'-Rabatt"},
        {"@home", "'@home"},
        {"\tTab", "'\tTab"},
        {"\rReturn", "'\rReturn"},
        {"Miete", "Miete"},
        {"a=b", "a=b"},
        {"", ""}
      ] do
    test "turns #{inspect(text)} into the cell #{inspect(cell)}" do
      assert Exports.cell(unquote(text)) == unquote(cell)
    end
  end

  describe "the period" do
    test "has inclusive, optional ends" do
      assert Exports.period(%{}) == {:ok, %{from: nil, to: nil}}

      assert Exports.period(%{"from" => "1.9.2026", "to" => ""}) ==
               {:ok, %{from: ~D[2026-09-01], to: nil}}

      assert Exports.period(%{"from" => "2026-09-01", "to" => "2026-09-01"}) ==
               {:ok, %{from: ~D[2026-09-01], to: ~D[2026-09-01]}}
    end

    test "refuses invalid dates and an end before the start" do
      for {params, message} <- [
            {%{"from" => "broken"}, "Ungültiges Datum „broken“."},
            {%{"from" => "2026-09-01", "to" => "31.02.2026"}, "Ungültiges Datum „31.02.2026“."},
            {%{"to" => "1999-12-31"},
             "Das Datum „1999-12-31“ liegt nicht zwischen 2000 und 2100."},
            {%{"from" => " "}, "Bitte ein Datum angeben."},
            {%{"from" => "2026-09-30", "to" => "29.09.2026"}, "„Bis“ liegt vor „Von“."}
          ],
          do: assert(Exports.period(params) == {:error, message})
    end
  end

  defp period(from \\ nil, to \\ nil),
    do: %{from: from && Date.from_iso8601!(from), to: to && Date.from_iso8601!(to)}

  describe "a household with every kind of expense" do
    setup do
      anna = person!("Anna")

      people =
        Map.new(~w(Ben Dora Emil Jürgen Xaver), fn name ->
          person = person!(name, anna.id)
          {name, person.id}
        end)
        |> Map.put("Anna", anna.id)

      {:ok, _xaver} =
        Participants.archive_participant(
          Scope.system(),
          Participants.get_participant!(Scope.system(), people["Xaver"])
        )

      {:ok, _settings} =
        Settings.update_settings(Scope.system(), %{group_name: ~s(WG <Zipfel> & "Co")})

      categories = Map.new(Categories.list_categories(Scope.system()), &{&1.name, &1.id})
      [anna, ben, dora, jue] = Enum.map(~w(Anna Ben Dora Jürgen), &people[&1])

      inputs = [
        {"Brötchen", "2026-08-30", 400, jue, [{anna, 0}, {jue, 0}], []},
        {"Café & Kuchen", "2026-09-01", 1201, anna, [{anna, 0}, {jue, 0}],
         category_id: categories["Restaurant"], notes: "lecker; „süß“"},
        {~s(Diner "NYC"), "2026-09-03", 0, ben, [{anna, 0}, {ben, 0}],
         original_currency: "USD", original_amount: 9000, fx_rate: 1.125, fx_source: :manual},
        {"Rückzahlung", "2026-09-05", 600, jue, [{anna, 0}], reimbursement: true},
        {"=SUMME(A1)", "2026-09-10", 500, ben, [{ben, 0}],
         category_id: categories["Lebensmittel"]},
        {~s(=Formel <&> "q"), "2026-09-05", 1000, anna, [{anna, 2}, {jue, 1}],
         split_mode: :shares, notes: "Zeile1\nZeile2\r\nZeile3; x"},
        {"Sushi", "2026-09-06", 0, anna, [{anna, 0}, {jue, 0}],
         original_currency: "JPY", original_amount: 2000, fx_rate: 160.5, fx_source: :manual},
        {"+49 Telefon", "2026-09-07", 2000, ben, [{anna, 2500}, {ben, 7500}],
         split_mode: :percent, category_id: categories["Haushalt"], notes: "@home"},
        {"-Rabatt", "2026-09-08", 750, dora, [{anna, 750}, {ben, 0}], split_mode: :amount},
        {"Gelöscht", "2026-09-09", 100, anna, [{anna, 0}], []},
        {"Konzert", "2026-12-04", 5000, ben, [{anna, 0}, {ben, 0}], []},
        {@long_title, "2026-09-12", 999, anna, [{anna, 0}, {ben, 0}, {dora, 0}], []},
        {"Heute", "2026-10-03", 300, anna, [{anna, 0}, {ben, 0}], []}
      ]

      ids =
        for {{title, date, cents, payer, parts, extra}, index} <- Enum.with_index(inputs, 1) do
          attrs =
            Map.merge(
              %{
                title: title,
                date: Date.from_iso8601!(date),
                paid_by_id: payer,
                amount_cents: cents,
                parts:
                  Enum.map(parts, fn {id, weight} -> %{participant_id: id, weight: weight} end)
              },
              Map.new(extra)
            )

          {:ok, expense} = Expenses.create_expense(scope_of(payer), attrs)
          assert expense.id == index
          expense.id
        end

      {:ok, _deleted} =
        Expenses.delete_expense(
          scope_of(anna),
          Expenses.get_expense!(Scope.system(), Enum.at(ids, 9))
        )

      %{people: people}
    end

    test "the CSV for German Excel has every expense with the shares of the people involved" do
      file = Exports.expenses_csv(Scope.system(), period(), @opts)

      assert {file.filename, file.content_type} ==
               {"kasse-ausgaben-2026-10-03.csv", "text/csv; charset=utf-8"}

      assert file.body ==
               "\uFEFF" <>
                 Enum.map_join(
                   [
                     "#{@header};Anteil Anna;Anteil Ben;Anteil Dora;Anteil Jürgen",
                     "1;30.08.2026;Brötchen;;Jürgen;4,00;4,00;EUR;;Ausgabe;Gleichmäßig;;2,00;;;2,00",
                     "2;01.09.2026;Café & Kuchen;Restaurant;Anna;12,01;12,01;EUR;;Ausgabe;Gleichmäßig;\"lecker; „süß“\";6,01;;;6,00",
                     "3;03.09.2026;\"Diner \"\"NYC\"\"\";;Ben;80,00;90,00;USD;1,125;Ausgabe;Gleichmäßig;;40,00;40,00;;",
                     "4;05.09.2026;Rückzahlung;;Jürgen;6,00;6,00;EUR;;Rückzahlung;Gleichmäßig;;6,00;;;",
                     "6;05.09.2026;\"'=Formel <&> \"\"q\"\"\";;Anna;10,00;10,00;EUR;;Ausgabe;Nach Anteilen;\"Zeile1\nZeile2\r\nZeile3; x\";6,67;;;3,33",
                     "7;06.09.2026;Sushi;;Anna;12,46;2000;JPY;160,5;Ausgabe;Gleichmäßig;;6,23;;;6,23",
                     "8;07.09.2026;'+49 Telefon;Haushalt;Ben;20,00;20,00;EUR;;Ausgabe;Nach Prozent;'@home;5,00;15,00;;",
                     "9;08.09.2026;'-Rabatt;;Dora;7,50;7,50;EUR;;Ausgabe;Nach Beträgen;;7,50;0,00;;",
                     "5;10.09.2026;'=SUMME(A1);Lebensmittel;Ben;5,00;5,00;EUR;;Ausgabe;Gleichmäßig;;;5,00;;",
                     "12;12.09.2026;#{@long_title};;Anna;9,99;9,99;EUR;;Ausgabe;Gleichmäßig;;3,33;3,33;3,33;",
                     "13;03.10.2026;Heute;;Anna;3,00;3,00;EUR;;Ausgabe;Gleichmäßig;;1,50;1,50;;",
                     "11;04.12.2026;Konzert;;Ben;50,00;50,00;EUR;;Ausgabe;Gleichmäßig;;25,00;25,00;;"
                   ],
                   &(&1 <> "\n")
                 )

      assert Exports.expenses_csv(Scope.system(), period("2026-12-01"), @opts).filename ==
               "kasse-ausgaben-ab-2026-12-01.csv"

      assert Exports.expenses_csv(Scope.system(), period(nil, "2026-08-31"), @opts).body ==
               "\uFEFF#{@header};Anteil Anna;Anteil Jürgen\n1;30.08.2026;Brötchen;;Jürgen;4,00;4,00;EUR;;Ausgabe;Gleichmäßig;;2,00;2,00\n"

      empty = Exports.expenses_csv(Scope.system(), period("2020-01-01", "2020-01-02"), @opts)

      assert {empty.filename, empty.body} ==
               {"kasse-ausgaben-2020-01-01_2020-01-02.csv", "\uFEFF#{@header}\n"}
    end

    test "the JSON has everything with shares", %{people: people} do
      file = Exports.expenses_json(Scope.system(), period("2026-09-03", "2026-09-06"), @opts)

      assert {file.filename, file.content_type} ==
               {"kasse-ausgaben-2026-09-03_2026-09-06.json", "application/json; charset=utf-8"}

      assert String.ends_with?(file.body, "}\n")
      assert file.body =~ ~s(\n  "currency": "EUR")
      json = JSON.decode!(file.body)

      assert Map.drop(json, ["expenses"]) == %{
               "group" => ~s(WG <Zipfel> & "Co"),
               "exported_at" => "2026-10-03T10:00:00Z",
               "from" => "2026-09-03",
               "to" => "2026-09-06",
               "currency" => "EUR",
               "participants" =>
                 for name <- ~w(Anna Ben Dora Emil Jürgen Xaver) do
                   %{"id" => people[name], "name" => name, "archived" => name == "Xaver"}
                 end
             }

      share = fn name, weight, cents ->
        %{
          "participant_id" => people[name],
          "name" => name,
          "weight" => weight,
          "amount_cents" => cents
        }
      end

      [diner, reimbursement, formula, sushi] = json["expenses"]

      assert Map.drop(diner, ["created_at", "updated_at"]) == %{
               "id" => 3,
               "date" => "2026-09-03",
               "title" => ~s(Diner "NYC"),
               "category_id" => nil,
               "category" => "",
               "paid_by" => people["Ben"],
               "paid_by_name" => "Ben",
               "amount_cents" => 8000,
               "is_reimbursement" => false,
               "split_mode" => "equal",
               "original_amount_minor" => 9000,
               "original_currency" => "USD",
               "fx_rate" => 1.125,
               "fx_source" => "manuell",
               "notes" => "",
               "recurring_id" => nil,
               "shares" => [share.("Anna", 1, 4000), share.("Ben", 1, 4000)]
             }

      assert diner["created_at"] =~ ~r/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/

      assert {reimbursement["is_reimbursement"], reimbursement["fx_source"],
              reimbursement["fx_rate"], reimbursement["shares"]} ==
               {true, "", 1.0, [share.("Anna", 1, 600)]}

      assert {formula["split_mode"], formula["notes"], formula["shares"]} ==
               {"shares", "Zeile1\nZeile2\r\nZeile3; x",
                [share.("Anna", 2, 667), share.("Jürgen", 1, 333)]}

      assert {sushi["original_amount_minor"], sushi["fx_rate"], sushi["amount_cents"]} ==
               {2000, 160.5, 1246}

      all = JSON.decode!(Exports.expenses_json(Scope.system(), period(), @opts).body)
      assert Enum.sort(Map.keys(all)) == ~w(currency expenses exported_at group participants)
      assert Enum.map(all["expenses"], & &1["id"]) == [1, 2, 3, 4, 6, 7, 8, 9, 5, 12, 13, 11]
      phone = Enum.find(all["expenses"], &(&1["id"] == 8))

      assert {phone["category"], phone["shares"]} ==
               {"Haushalt", [share.("Anna", 2500, 500), share.("Ben", 7500, 1500)]}
    end
  end

  describe "the JSON file" do
    test "keeps its keys in the documented order" do
      anna = person!("Anna")
      ben = person!("Ben", anna.id)
      food = Enum.find(Categories.list_categories(Scope.system()), &(&1.name == "Lebensmittel"))

      {:ok, expense} =
        Expenses.create_expense(scope_of(anna.id), %{
          title: "Rewe",
          date: ~D[2026-09-01],
          paid_by_id: anna.id,
          category_id: food.id,
          amount_cents: 1001,
          notes: "Wochenende",
          parts: [%{participant_id: anna.id, weight: 0}, %{participant_id: ben.id, weight: 0}]
        })

      Repo.update_all(where(Expense, id: ^expense.id),
        set: [
          inserted_at: ~U[2026-09-01 18:00:00.123456Z],
          updated_at: ~U[2026-09-02 07:30:00.000000Z]
        ]
      )

      assert Exports.expenses_json(Scope.system(), period("2026-09-01", "2026-09-30"), @opts).body ==
               """
               {
                 "group": "Kasse",
                 "exported_at": "2026-10-03T10:00:00Z",
                 "from": "2026-09-01",
                 "to": "2026-09-30",
                 "currency": "EUR",
                 "participants": [
                   {
                     "id": #{anna.id},
                     "name": "Anna",
                     "archived": false
                   },
                   {
                     "id": #{ben.id},
                     "name": "Ben",
                     "archived": false
                   }
                 ],
                 "expenses": [
                   {
                     "id": #{expense.id},
                     "date": "2026-09-01",
                     "title": "Rewe",
                     "category_id": #{food.id},
                     "category": "Lebensmittel",
                     "paid_by": #{anna.id},
                     "paid_by_name": "Anna",
                     "amount_cents": 1001,
                     "is_reimbursement": false,
                     "split_mode": "equal",
                     "original_amount_minor": 1001,
                     "original_currency": "EUR",
                     "fx_rate": 1.0,
                     "fx_source": "",
                     "notes": "Wochenende",
                     "recurring_id": null,
                     "shares": [
                       {
                         "participant_id": #{anna.id},
                         "name": "Anna",
                         "weight": 1,
                         "amount_cents": 500
                       },
                       {
                         "participant_id": #{ben.id},
                         "name": "Ben",
                         "weight": 1,
                         "amount_cents": 501
                       }
                     ],
                     "created_at": "2026-09-01T18:00:00Z",
                     "updated_at": "2026-09-02T07:30:00Z"
                   }
                 ]
               }
               """
    end
  end
end
