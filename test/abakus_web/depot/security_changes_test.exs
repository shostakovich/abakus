defmodule AbakusWeb.Depot.SecurityChangesTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Securities.Security
  alias AbakusWeb.Depot.SecurityChanges

  @yahoo %Security{quote_feed: :yahoo, symbol: "VGWL.DE", isin: "IE00B3RBWM25", retired: false}
  @manual %Security{quote_feed: :manual, symbol: nil, isin: nil, retired: false}

  defp of(security, params, usage \\ %{held: false, benchmark: false}),
    do: SecurityChanges.of(security, params, usage)

  describe "of/2" do
    test "a new symbol or a switch to Yahoo loads the prices anew" do
      assert of(@yahoo, %{"symbol" => "VWRL.AS"}).source == :new
      assert of(@manual, %{"quote_feed" => "yahoo", "symbol" => "VGWL.DE"}).source == :new
    end

    test "the same symbol, one with spaces around it or none changes no source" do
      assert of(@yahoo, %{"quote_feed" => "yahoo", "symbol" => " VGWL.DE "}).source == nil
      assert of(@manual, %{"quote_feed" => "yahoo", "symbol" => ""}).source == nil
      assert of(@yahoo, %{}).source == nil
    end

    test "a switch to manual stops Yahoo" do
      assert of(@yahoo, %{"quote_feed" => "manual"}).source == :stop
      assert of(@manual, %{"quote_feed" => "manual"}).source == nil
    end

    test "tells an added, changed and removed ISIN apart, in capitals and without spaces" do
      assert of(@manual, %{"isin" => "ie00 b3rb wm25"}).isin == :added
      assert of(@yahoo, %{"isin" => "IE00B5SSQT16"}).isin == :changed
      assert of(@yahoo, %{"isin" => " "}).isin == :removed
      assert of(@yahoo, %{"isin" => "ie00b3rbwm25"}).isin == nil
      assert of(@manual, %{"isin" => ""}).isin == nil
    end

    test "an invalid ISIN changes nothing yet" do
      assert of(@manual, %{"isin" => "IE00B3RB"}).isin == nil
      assert of(@yahoo, %{"isin" => "IE00B3RBWM26"}).isin == nil
    end
  end

  describe "isin_help/2" do
    test "says what an added ISIN fetches, and nothing without a change" do
      assert {"TER, Fondsgröße, Länder, Sektoren und Dividenden werden von DivvyDiary geholt.",
              nil} =
               SecurityChanges.isin_help(of(@manual, %{"isin" => "IE00B3RBWM25"}), true)

      assert SecurityChanges.isin_help(of(@manual, %{"isin" => "IE00B3RBWM25"}), false) == nil
      assert SecurityChanges.isin_help(of(@yahoo, %{}), true) == nil
    end

    test "warns before a changed or removed ISIN drops the data of the old one" do
      changed = of(@yahoo, %{"isin" => "IE00B5SSQT16"})

      assert {"Die Fondsdaten der bisherigen ISIN werden entfernt und neu von DivvyDiary geholt.",
              :warning} = SecurityChanges.isin_help(changed, true)

      assert {"Die Fondsdaten der bisherigen ISIN werden entfernt.", :warning} =
               SecurityChanges.isin_help(changed, false)

      assert {"TER, Fondsgröße, Länder, Sektoren und Dividenden von DivvyDiary werden entfernt.",
              :warning} = SecurityChanges.isin_help(of(@yahoo, %{"isin" => ""}), true)
    end
  end

  describe "retiring" do
    test "a toggled switch retires or brings back" do
      assert of(@yahoo, %{"retired" => "true"}).retired == :retire
      assert of(%{@yahoo | retired: true}, %{"retired" => "false"}).retired == :reactivate
      assert of(@yahoo, %{"retired" => "false"}).retired == nil
    end

    test "retired_help/1 warns while it is held or a benchmark" do
      retire = %{"retired" => "true"}

      assert SecurityChanges.retired_help(of(@yahoo, retire)) ==
               {"Ausgemusterte Wertpapiere holen keine Kurse und Fondsdaten.", nil}

      assert SecurityChanges.retired_help(of(@yahoo, retire, %{held: true, benchmark: false})) ==
               {"Noch im Bestand: die Kurse bleiben dann stehen.", :warning}

      assert SecurityChanges.retired_help(of(@yahoo, retire, %{held: false, benchmark: true})) ==
               {"Als Benchmark gewählt: die Kurse bleiben dann stehen.", :warning}
    end

    test "retired_help/1 names what a security brought back fetches again" do
      back = %{"retired" => "false"}

      assert SecurityChanges.retired_help(of(%{@yahoo | retired: true}, back)) ==
               {"Kurse und Fondsdaten werden wieder geholt.", nil}

      assert SecurityChanges.retired_help(of(%{@manual | retired: true}, back)) ==
               {"Ausgemusterte Wertpapiere holen keine Kurse und Fondsdaten.", nil}

      assert SecurityChanges.retired_help(
               of(%{@manual | retired: true}, Map.put(back, "isin", "IE00B3RBWM25"))
             ) == {"Fondsdaten werden wieder geholt.", nil}
    end

    test "confirmation/1 asks before retiring a security still held or compared with" do
      retire = %{"retired" => "true", "quote_feed" => "manual"}

      assert %{question: "Wertpapier ausmustern?", label: "Ausmustern", text: text} =
               SecurityChanges.confirmation(of(@yahoo, retire, %{held: true, benchmark: true}))

      assert text == "Noch im Bestand und als Benchmark gewählt: die Kurse bleiben dann stehen."
      assert SecurityChanges.confirmation(of(@yahoo, retire)) == nil
    end
  end

  test "yahoo_name/2 names whose ISIN it is, warning when it is clearly another" do
    assert SecurityChanges.yahoo_name(
             {:ok, %{name: "Vanguard FTSE All-World UCITS ETF USD Dis"}},
             "Vanguard FTSE All-World"
           ) == {"Laut Yahoo: Vanguard FTSE All-World UCITS ETF USD Dis.", nil}

    assert SecurityChanges.yahoo_name(
             {:ok, %{name: "iShares Core MSCI EM IMI"}},
             "Vanguard FTSE All-World"
           ) ==
             {"Laut Yahoo: iShares Core MSCI EM IMI. Ein anderes Wertpapier?", :warning}

    assert SecurityChanges.yahoo_name(:searching, "x") == {"Suche bei Yahoo …", nil}

    assert SecurityChanges.yahoo_name({:error, "Yahoo kennt diese ISIN nicht."}, "x") ==
             {"Yahoo kennt diese ISIN nicht.", nil}
  end

  test "other_security/2 is Yahoo's listing when it is clearly another security" do
    listing = %{name: "iShares Core MSCI EM IMI", symbol: "IS3N.DE"}

    assert SecurityChanges.other_security({:ok, listing}, "Vanguard FTSE All-World") == listing

    assert SecurityChanges.other_security(
             {:ok, %{name: "Vanguard FTSE All-World UCITS ETF", symbol: "VWRL.AS"}},
             "Vanguard FTSE All-World"
           ) == nil

    assert SecurityChanges.other_security(:searching, "x") == nil
    assert SecurityChanges.other_security({:error, "Yahoo kennt diese ISIN nicht."}, "x") == nil
  end

  test "source_help/1 warns before new prices or the end of Yahoo" do
    assert SecurityChanges.source_help(of(@yahoo, %{"symbol" => "VWRL.AS"})) ==
             "Die Kurse werden neu von Yahoo geladen."

    assert SecurityChanges.source_help(of(@yahoo, %{"quote_feed" => "manual"})) ==
             "Neue Kurse kommen dann nicht mehr von Yahoo; die bisherigen bleiben."

    assert SecurityChanges.source_help(of(@yahoo, %{})) == nil
  end

  describe "confirmation/1" do
    test "asks before removing the ISIN or stopping Yahoo, or both" do
      assert %{question: "ISIN entfernen?", label: "Entfernen"} =
               SecurityChanges.confirmation(of(@yahoo, %{"isin" => ""}))

      assert %{question: "Kursabruf beenden?", label: "Beenden"} =
               SecurityChanges.confirmation(of(@yahoo, %{"quote_feed" => "manual"}))

      assert %{question: "ISIN entfernen und Kursabruf beenden?", label: "Speichern"} =
               SecurityChanges.confirmation(of(@yahoo, %{"quote_feed" => "manual", "isin" => ""}))
    end

    test "asks before taking another security's ISIN, naming the symbol it keeps" do
      changes = of(@yahoo, %{"isin" => "IE00BKM4GZ66"})

      assert SecurityChanges.confirmation(changes, "EM IMI", "VGWL.DE") == %{
               question: "ISIN eines anderen Wertpapiers übernehmen?",
               text: "Laut Yahoo gehört sie zu EM IMI; die Kurse kommen weiter von VGWL.DE.",
               label: "Übernehmen"
             }

      assert %{text: "Laut Yahoo gehört sie zu EM IMI. Neue Kurse kommen" <> _rest} =
               SecurityChanges.confirmation(
                 of(@yahoo, %{"isin" => "IE00BKM4GZ66", "quote_feed" => "manual"}),
                 "EM IMI",
                 nil
               )

      assert SecurityChanges.confirmation(changes, nil, "VGWL.DE") == nil
    end

    test "saves without asking otherwise" do
      for params <- [%{}, %{"isin" => "IE00B5SSQT16"}, %{"symbol" => "VWRL.AS"}] do
        assert SecurityChanges.confirmation(of(@yahoo, params)) == nil
      end
    end
  end
end
