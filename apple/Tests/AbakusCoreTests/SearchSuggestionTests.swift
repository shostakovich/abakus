import AbakusCore
import Foundation
import Testing

@Suite struct SearchSuggestionTests {
    private func suggestions(_ text: String, allAccounts: Bool = false) -> [RegisterSearchSuggestion] {
        var test = TestBudget()
        _ = try? test.add(test.girokonto, -40, payee: "REWE")
        _ = try? test.add(test.girokonto, -10, payee: "Aral")
        return RegisterSearchSuggestions(budget: test.budget, isAllAccounts: allAccounts, today: october23)
            .suggestions(for: text)
    }

    private func labels(_ text: String, allAccounts: Bool = false) -> [String] {
        suggestions(text, allAccounts: allAccounts).map { $0.prefix + "|" + $0.description }
    }

    @Test func emptyTextHasNoSuggestions() {
        #expect(suggestions("  ").isEmpty)
    }

    @Test func plainTextStartsWithTheDatesHintAndEndsWithFreeTextSearches() {
        let items = labels("rew")
        #expect(items.first == "Datum|(<i>Datum als TT.MM.JJ eingeben</i>)")
        #expect(items.contains("Empfänger: |REWE"))
        #expect(
            items.suffix(4) == [
                "|„<b>rew</b>“ in allen Feldern suchen", "Empfänger: |„<b>rew</b>“ im Empfänger suchen",
                "Kategorie: |„<b>rew</b>“ in der Kategorie suchen", "Memo: |„<b>rew</b>“ im Memo suchen",
            ])
    }

    @Test func aDateOffersOnBeforeAndAfter() {
        let items = suggestions("23.10.26")
        #expect(
            items.prefix(3).map(\.description) == [
                "Am <b>23.10.26</b>", "Am oder vor dem <b>23.10.26</b>", "Am oder nach dem <b>23.10.26</b>",
            ])
        #expect(items.first?.searchText == "Am:23.10.26")
        #expect(!items.contains { $0.prefix == "Datum" })
    }

    @Test func aDatePrefixWithoutValueShowsThePattern() {
        let on = suggestions("Am:").first { $0.prefix == "Am:" }
        #expect(on?.description == "Am <b>TT.MM.JJ</b>")
        #expect(on?.searchText == "")
    }

    @Test func aNumberOffersAllSixAmountSearches() {
        let amounts = suggestions("50").filter { $0.icon == .outflow || $0.icon == .inflow }
        #expect(
            amounts.map(\.description) == [
                "Ausgang gleich <b>50,00€</b>", "Ausgang mindestens <b>50,00€</b>",
                "Ausgang höchstens <b>50,00€</b>", "Eingang gleich <b>50,00€</b>",
                "Eingang mindestens <b>50,00€</b>", "Eingang höchstens <b>50,00€</b>",
            ])
        #expect(
            amounts.map(\.searchText) == [
                "Ausgang:50", "Ausgang: >50", "Ausgang: <50", "Eingang:50", "Eingang: >50", "Eingang: <50",
            ])
    }

    @Test func greaterThanPicksTheMoreVariants() {
        let amounts = suggestions(">50").filter { $0.icon == .outflow || $0.icon == .inflow }
        #expect(amounts.map(\.searchText) == ["Ausgang: >50", "Eingang: >50"])
    }

    @Test func outflowPrefixShowsZeroPlaceholders() {
        let amounts = suggestions("Ausg").filter { $0.icon == .outflow }
        #expect(amounts.first?.description == "Ausgang gleich <b>0,00</b>")
        #expect(amounts.count == 3)
    }

    @Test func isPrefixListsApprovalAndClearedStates() {
        let items = suggestions("Ist:").map(\.searchText)
        #expect(items.contains("Ist: Bestätigt"))
        #expect(items.contains("Ist: Gebucht oder abgeglichen"))
        #expect(items.contains("Ist:Fehler"))
    }

    @Test func payeePrefixOffersBlankAndEveryPayee() {
        let payees = suggestions("Empfänger:").filter { $0.prefix == "Empfänger: " && !$0.id.hasPrefix("find:") }
        #expect(payees.first?.isBlank == true)
        #expect(payees.first?.searchText == "Empfänger: ")
        #expect(payees.map(\.searchText).contains("Empfänger: REWE"))
    }

    @Test func categoriesShowMastersBoldAndSubsIndented() {
        let items = suggestions("Groc").filter { $0.prefix == "Kategorie: " && !$0.id.hasPrefix("find:") }
        #expect(items.map(\.description) == ["<b>Everyday Expenses</b>", "Groceries"])
        #expect(items.last?.indent == 15)
        #expect(items.last?.searchText == "Kategorie: Everyday Expenses: Groceries")
    }

    @Test func masterAndSubTypedWithAColon() {
        let items = suggestions("Every: Fu").filter { $0.prefix == "Kategorie: " && !$0.id.hasPrefix("find:") }
        #expect(items.map(\.description).contains("Fuel"))
        #expect(!items.map(\.description).contains("Groceries"))
    }

    @Test func incomeOffersAMonthExample() {
        let income = suggestions("Einnahmen:").first { $0.prefix == "Einnahmen:" }
        #expect(income?.description == "(<i>Monat eingeben, etwa „Einnahmen: Oktober 2026“</i>)")
        let typed = suggestions("Einnahmen: März").first { $0.prefix == "Einnahmen:" }
        #expect(typed?.searchText == "Einnahmen: März")
    }

    @Test func accountsOnlyInAllAccounts() {
        #expect(!labels("Konto:").contains { $0.hasPrefix("Konto: ") })
        let items = suggestions("Konto:", allAccounts: true).filter { $0.prefix == "Konto: " }
        #expect(items.first?.description == "<b>Budgetkonten</b>")
        #expect(items.map(\.searchText).contains("Konto: Girokonto"))
    }

    @Test func allAccountsPutsAccountsSecond() {
        let prefixes = suggestions("g", allAccounts: true).map(\.prefix)
        let accountIndex = prefixes.firstIndex(of: "Konto: ")
        let payeeIndex = prefixes.firstIndex(of: "Empfänger: ")
        #expect(accountIndex != nil && payeeIndex != nil && accountIndex! < payeeIndex!)
    }

    @Test func allAccountsKeepsTheSingleAccountOrderAroundTheAccountGroup() {
        let single = suggestions("ei").map(\.prefix)
        let all = suggestions("ei", allAccounts: true).map(\.prefix).filter { $0 != "Konto: " }
        #expect(single.contains("Einnahmen:") && single.contains("Eingang:"))
        #expect(all == single)
    }

    @Test func typedMarkupIsEscaped() {
        #expect(labels("<b>").contains("|„<b>&lt;b&gt;</b>“ in allen Feldern suchen"))
    }
}
