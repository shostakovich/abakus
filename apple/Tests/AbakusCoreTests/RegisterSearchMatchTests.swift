import AbakusCore
import Foundation
import Testing

private struct SearchFixture {
    var test = TestBudget()
    var giro: String { test.girokonto }

    init() {
        let groceries = test.groceries
        let fuel = test.category("Everyday Expenses", "Fuel")
        let household = test.category("Everyday Expenses", "Household Goods")
        add(
            Transaction(
                id: "REWE", accountId: giro, date: date("2026-10-10"), categoryId: groceries, memo: "Milch",
                amount: -40), payee: "REWE")
        add(
            Transaction(
                id: "ARAL", accountId: giro, date: date("2026-10-12"), categoryId: fuel, amount: -62.4,
                cleared: .cleared), payee: "Aral")
        add(
            Transaction(
                id: "SAVE", accountId: giro, date: date("2026-10-14"), amount: -100
            ).transferring(to: test.tagesgeld))
        add(
            Transaction(
                id: "DEPOT", accountId: giro, date: date("2026-10-15"), categoryId: household, amount: -200,
                cleared: .reconciled
            ).transferring(to: test.depot))
        add(
            Transaction(
                id: "SALARY", accountId: giro, date: date("2026-10-01"),
                categoryId: test.budget.readyToAssignCategoryId,
                amount: 3000, cleared: .cleared), payee: "Arbeitgeber")
        add(
            Transaction(
                id: "SPLIT", accountId: giro, date: date("2026-10-20"), amount: -50,
                subtransactions: [
                    Subtransaction(
                        id: "S1", transactionId: "SPLIT", amount: -30, categoryId: groceries, memo: "Essen"),
                    Subtransaction(
                        id: "S2", transactionId: "SPLIT", amount: -20, categoryId: household, memo: "Seife"),
                ]), payee: "Kaufland")
        add(
            Transaction(
                id: "BANK", accountId: giro, date: date("2026-10-21"), amount: -9.99, cleared: .cleared,
                approved: false,
                source: .bank), payee: "Netflix")
    }

    private mutating func add(_ transaction: Transaction, payee: String? = nil) {
        try! test.budget.apply(.addTransaction(transaction, payeeName: payee))
    }

    mutating func addSplitWithALinePayee() {
        let split = Transaction(
            id: "DM", accountId: giro, date: date("2026-10-22"), categoryId: EntityID.splitCategory, amount: -15,
            subtransactions: [
                Subtransaction(id: "D1", transactionId: "DM", amount: -10),
                Subtransaction(id: "D2", transactionId: "DM", amount: -5),
            ])
        try! test.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: split, payeeName: "Rossmann", subPayeeNames: ["D2": "dm"], isNew: true)))
    }

    var budget: Budget { test.budget }

    func visible(_ text: String) -> [String] {
        let query = RegisterSearchQuery(text, decimalSeparator: ",")
        let environment = RegisterSearchEnvironment(budget: budget, today: october23)
        return budget.transactions(inAccount: giro).filter { query.match($0, in: environment).isVisible }
            .map(\.id).filter { $0 != test.budget.transactions.first!.id }.sorted()
    }

    func match(_ text: String, _ id: String) -> RegisterSearchMatch {
        let environment = RegisterSearchEnvironment(budget: budget, today: october23)
        return RegisterSearchQuery(text, decimalSeparator: ",").match(budget.transaction(withId: id)!, in: environment)
    }
}

@Suite struct RegisterSearchMatchTests {
    private let fixture = SearchFixture()

    @Test func anyFieldMatchesPayeeCategoryAndMemo() {
        #expect(fixture.visible("rew") == ["REWE"])
        #expect(fixture.visible("fuel") == ["ARAL"])
        #expect(fixture.visible("milch") == ["REWE"])
    }

    @Test func anyFieldFindsTransferPayees() {
        #expect(fixture.visible("Transfer : Tages") == ["SAVE"])
    }

    @Test func numericTextFindsAmountsAsWritten() {
        #expect(fixture.visible("62,40") == ["ARAL"])
        #expect(fixture.visible("62,4") == ["ARAL"])
        #expect(fixture.visible("2,4") == ["ARAL"])
        #expect(fixture.visible("9,99") == ["BANK"])
        #expect(fixture.visible("40") == ["ARAL", "REWE"])
        #expect(fixture.visible("3000,00") == ["SALARY"])
    }

    @Test func numericTextFindsSplitLines() {
        #expect(fixture.visible("30,00") == ["SPLIT"])
        let match = fixture.match("30,00", "SPLIT")
        #expect(match.subMatches("S1") && !match.subMatches("S2"))
    }

    @Test func anyFieldFindsTheCategoryAndMemoOfSplitParts() {
        #expect(fixture.visible("seife") == ["SPLIT"])
        let match = fixture.match("household", "SPLIT")
        #expect(match.isVisible && !match.subMatches("S1") && match.subMatches("S2"))
    }

    @Test func anyFieldFindsThePayeeOfSplitParts() {
        var fixture = SearchFixture()
        fixture.addSplitWithALinePayee()
        #expect(fixture.visible("dm") == ["DM"])
        let match = fixture.match("dm", "DM")
        #expect(!match.subMatches("D1") && match.subMatches("D2"))
    }

    @Test func payeeTermsMatchAPartsOwnPayeeElseTheTransactions() {
        var fixture = SearchFixture()
        fixture.addSplitWithALinePayee()
        let own = fixture.match("Empfänger: dm", "DM")
        #expect(own.isVisible && !own.subMatches("D1") && own.subMatches("D2"))
        let parent = fixture.match("Empfänger: Rossmann", "DM")
        #expect(parent.subMatches("D1") && !parent.subMatches("D2"))
    }

    @Test func termsAreAnded() {
        #expect(fixture.visible("Empfänger: Aral, Ausgang: 62,40") == ["ARAL"])
        #expect(fixture.visible("Empfänger: Aral, Memo: Milch") == [])
    }

    @Test func payeeValuesAreOred() {
        #expect(fixture.visible("Empfänger: Aral, Empfänger: REWE") == ["ARAL", "REWE"])
    }

    @Test func existingPayeeNameMatchesExactly() {
        #expect(fixture.visible("Empfänger: rewe") == ["REWE"])
        #expect(fixture.visible("Empfänger: Ara") == ["ARAL"])
    }

    @Test func emptyPayeeMatchesBlankPayees() {
        #expect(fixture.visible("Empfänger:") == [])
    }

    @Test func categoryMatchesDisplayNames() {
        #expect(fixture.visible("Kategorie: Everyday Expenses: Fuel") == ["ARAL"])
        #expect(fixture.visible("Kategorie: Everyday") == ["ARAL", "DEPOT", "REWE", "SPLIT"])
    }

    @Test func emptyCategoryMatchesUncategorisedRows() {
        #expect(fixture.visible("Kategorie:") == ["BANK", "SAVE"])
    }

    @Test func memoTerm() {
        #expect(fixture.visible("Memo: milch") == ["REWE"])
        #expect(fixture.visible("Memo:").contains("ARAL"))
    }

    @Test func namesMatchIgnoringCaseEmojiSharpSAndHowUmlautsAreWritten() throws {
        var test = TestBudget()
        let bakery = try test.add(test.girokonto, -3, payee: "🥨 Bäckerei Straße")
        let other = try test.add(test.girokonto, -4, payee: "Edeka")
        let environment = RegisterSearchEnvironment(budget: test.budget, today: october23)
        func visible(_ text: String) -> [String] {
            [bakery, other].filter { id in
                RegisterSearchQuery(text).match(test.budget.transaction(withId: id)!, in: environment).isVisible
            }
        }
        #expect(visible("BÄCKEREI STRASSE") == [bakery])
        #expect(visible("Ba\u{308}ckerei") == [bakery])
        #expect(visible("Empfänger: bäckerei strasse") == [bakery])
        #expect(visible("Empfänger: 🥨 Bäckerei") == [bakery])
    }

    @Test func clearedStatusTerms() {
        #expect(fixture.visible("Ist: Abgeglichen") == ["DEPOT"])
        #expect(fixture.visible("Ist: Gebucht") == ["ARAL", "BANK", "SALARY"])
        #expect(fixture.visible("Ist: Gebucht oder abgeglichen") == ["ARAL", "BANK", "DEPOT", "SALARY"])
        #expect(!fixture.visible("Ist: Nicht abgeglichen").contains("DEPOT"))
    }

    @Test func approvalAndErrorLevels() {
        #expect(fixture.visible("Ist: Unbestätigt") == ["BANK"])
        #expect(fixture.visible("Ist: Erinnerung") == ["BANK"])
        #expect(!fixture.visible("Ist: Bestätigt").contains("BANK"))
        #expect(fixture.visible("Ist: Nicht kategorisiert") == [])
    }

    @Test func expenseExcludesIncomeAndBudgetTransfers() {
        let expense = fixture.visible("Ist: Ausgabe")
        #expect(expense.contains("REWE"))
        #expect(expense.contains("DEPOT"))
        #expect(!expense.contains("SALARY"))
        #expect(!expense.contains("SAVE"))
        #expect(fixture.visible("Ist: Einnahme oder Ausgabe").contains("SALARY"))
    }

    @Test func dateTerms() {
        #expect(fixture.visible("Am: 10.10.26") == ["REWE"])
        #expect(fixture.visible("Ab: 20.10.26") == ["BANK", "SPLIT"])
        #expect(fixture.visible("Bis: 01.10.26").contains("SALARY"))
        #expect(fixture.visible("Am: 32.13.26") == [])
    }

    @Test func outflowComparisons() {
        #expect(fixture.visible("Ausgang: 40") == ["REWE"])
        #expect(fixture.visible("Ausgang: >100") == ["DEPOT", "SAVE"])
        #expect(fixture.visible("Ausgang: <10").contains("SALARY"))
        #expect(fixture.visible("Ausgang: <10").contains("BANK"))
        #expect(!fixture.visible("Ausgang: <10").contains("REWE"))
    }

    @Test func inflowComparisons() {
        #expect(fixture.visible("Eingang: 3000") == ["SALARY"])
        #expect(fixture.visible("Eingang: >1000") == ["SALARY"])
        #expect(fixture.visible("Eingang: <0").contains("REWE"))
        #expect(fixture.visible("Eingang: abc") == [])
    }

    @Test func accountGroupsFollowTheSidebarGroups() throws {
        var test = TestBudget()
        let giro = try test.add(test.girokonto, -1)
        let depot = try test.add(test.depot, -2)
        test.budget.accounts[2].closed = true
        let environment = RegisterSearchEnvironment(budget: test.budget, today: october23)
        func visible(_ text: String) -> [String] {
            [giro, depot].filter { id in
                RegisterSearchQuery(text).match(test.budget.transaction(withId: id)!, in: environment).isVisible
            }
        }
        #expect(visible("Konto: Budgetkonten") == [giro])
        #expect(visible("Konto: Geschlossene Konten") == [depot])
        #expect(visible("Konto: Geschlossene Trackingkonten") == [depot])
        #expect(visible("Konto: Geschlossene Budgetkonten") == [])
        #expect(visible("Konto: Trackingkonten") == [])
        #expect(RegisterSearchQuery.accountGroups.first == "Budgetkonten")
    }

    @Test func incomeTogetherWithAnotherTermNeedsOneSplitLineMatchingBoth() throws {
        var test = TestBudget()
        let split = Transaction(
            id: "PAY", accountId: test.girokonto, date: date("2026-10-30"), amount: 100,
            subtransactions: [
                Subtransaction(
                    id: "X", transactionId: "PAY", amount: 80, categoryId: test.budget.readyToAssignCategoryId,
                    memo: "salary"),
                Subtransaction(
                    id: "Y", transactionId: "PAY", amount: 20, categoryId: test.groceries, memo: "bonus"),
            ])
        try test.budget.apply(.addTransaction(split))
        let environment = RegisterSearchEnvironment(budget: test.budget, today: october23)
        let transaction = try #require(test.budget.transaction(withId: "PAY"))
        #expect(!RegisterSearchQuery("Einnahmen: October, Memo: bonus").match(transaction, in: environment).isVisible)
        let salary = RegisterSearchQuery("Einnahmen: October, Memo: salary").match(transaction, in: environment)
        #expect(salary.isVisible && salary.subMatches("X") && !salary.subMatches("Y"))
    }

    @Test func incomeForMonth() {
        #expect(fixture.visible("Einnahmen: October 2026") == ["SALARY"])
        #expect(fixture.visible("Einnahmen: Oktober") == ["SALARY"])
        #expect(fixture.visible("Einnahmen: November 2026") == [])
    }

    @Test func accountTermsMatchNamesAndGroups() {
        #expect(fixture.visible("Konto: giro").count == 7)
        #expect(fixture.visible("Konto: Budgetkonten").count == 7)
        #expect(fixture.visible("Konto: Trackingkonten") == [])
    }

    @Test func splitShowsWhenALineMatchesAndStrikesTheOthers() {
        let match = fixture.match("Memo: Essen", "SPLIT")
        #expect(match.isVisible)
        #expect(match.subMatches("S1"))
        #expect(!match.subMatches("S2"))
        #expect(match.expandsSplit)
    }

    @Test func splitPayeeMatchKeepsEveryLine() {
        let match = fixture.match("Empfänger: Kaufland", "SPLIT")
        #expect(match.isVisible)
        #expect(match.parentMatches)
        #expect(!match.expandsSplit)
    }

    @Test func searchTotalOfASplitCountsOnlyMatchingLines() {
        let match = fixture.match("Memo: Essen", "SPLIT")
        #expect(match.searchAmount(of: fixture.budget.transaction(withId: "SPLIT")!) == -30)
    }

    @Test func nonSplitSearchAmountIsTheAmount() {
        #expect(fixture.match("rewe", "REWE").searchAmount(of: fixture.budget.transaction(withId: "REWE")!) == -40)
    }
}
