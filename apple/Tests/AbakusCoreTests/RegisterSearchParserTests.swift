import AbakusCore
import Foundation
import Testing

@Suite struct RegisterSearchParserTests {
    @Test func bareTextSearchesEveryField() {
        #expect(RegisterSearchQuery("rewe").items == [.anyField("rewe")])
    }

    @Test func termsAreSplitOnCommasAndTrimmed() {
        #expect(RegisterSearchQuery(" rewe ,  , milk ").items == [.anyField("rewe"), .anyField("milk")])
    }

    @Test func emptyTextHasNoItems() {
        #expect(RegisterSearchQuery(" , ").isEmpty)
    }

    @Test func prefixesAreCaseInsensitive() {
        #expect(RegisterSearchQuery("EMPFÄNGER: Aral").items == [.payees(["Aral"])])
        #expect(RegisterSearchQuery("memo:Brot").items == [.memo("Brot")])
    }

    @Test func unknownPrefixSearchesTheValueInEveryField() {
        #expect(RegisterSearchQuery("foo:bar").items == [.anyField("bar")])
    }

    @Test func repeatedPayeeAndCategoryTermsMerge() {
        let query = RegisterSearchQuery("Empfänger: A, Empfänger: B, Kategorie: X, Kategorie: Y")
        #expect(query.items == [.payees(["A", "B"]), .categories(["X", "Y"])])
    }

    @Test func accountTermsMerge() {
        #expect(
            RegisterSearchQuery("Konto: Giro, Konto: Budgetkonten").items == [
                .accounts(["Giro", "Budgetkonten"])
            ])
    }

    @Test func emptyPayeeValueSearchesBlankPayees() {
        #expect(RegisterSearchQuery("Empfänger:").items == [.payees([""])])
    }

    @Test func isTermsMapToTheirItems() {
        let cases: [(String, SearchItem)] = [
            ("Ist: Bestätigt", .approved(true)), ("Ist:unbestätigt", .approved(false)),
            ("Ist:Fehler", .errorLevel(.error)),
            ("Ist:Erinnerung", .errorLevel(.forReview)), ("Ist: Nicht kategorisiert", .errorLevel(.needsCategory)),
            ("Ist: Gebucht oder abgeglichen", .clearedOrReconciled), ("Ist:Nicht abgeglichen", .unreconciled),
            ("Ist:Ausgabe", .expense), ("Ist: Einnahme oder Ausgabe", .incomeOrExpense),
            ("Ist: Gebucht", .cleared(.cleared)),
            ("Ist: Vorgemerkt", .cleared(.uncleared)), ("Ist:Abgeglichen", .cleared(.reconciled)),
        ]
        for (text, item) in cases {
            #expect(RegisterSearchQuery(text).items == [item], "\(text)")
        }
    }

    @Test func unknownIsValueIsIgnored() {
        #expect(RegisterSearchQuery("Ist: Ausstehend").isEmpty)
    }

    @Test func dateTerms() {
        #expect(
            RegisterSearchQuery("Am: 1.10.26, Ab:2.10.26, Bis: 3.10.26").items == [
                .date(.on, "1.10.26"), .date(.after, "2.10.26"), .date(.before, "3.10.26"),
            ])
    }

    @Test func amountTermsWithComparisons() {
        #expect(
            RegisterSearchQuery("Ausgang: 50, Ausgang: >50, Ausgang:< 50").items == [
                .amount(.outflowEquals, "50"), .amount(.outflowMore, "50"), .amount(.outflowLess, "50"),
            ])
        #expect(
            RegisterSearchQuery("Eingang:5, Eingang:>5, Eingang:<5").items == [
                .amount(.inflowEquals, "5"), .amount(.inflowMore, "5"), .amount(.inflowLess, "5"),
            ])
    }

    @Test func incomeTerm() {
        #expect(RegisterSearchQuery("Einnahmen: October").items == [.incomeFor("October")])
    }

    @Test func commaBetweenDigitsIsADecimalPointWithCommaLocales() {
        #expect(
            RegisterSearchQuery("Ausgang: 12,50", decimalSeparator: ",").items == [.amount(.outflowEquals, "12.50")])
        #expect(RegisterSearchQuery("Ausgang: 12,50").items == [.amount(.outflowEquals, "12"), .anyField("50")])
    }
}
