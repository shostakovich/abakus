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
                id: "ARAL", accountId: giro, date: date("2026-10-12"), categoryId: fuel, amount: -1062.4,
                cleared: .cleared), payee: "Aral")
        add(
            Transaction(
                id: "SAVE", accountId: giro, date: date("2026-10-14"), amount: -100
            ).transferring(to: test.tagesgeld))
        add(
            Transaction(
                id: "SALARY", accountId: giro, date: date("2026-10-01"),
                categoryId: test.budget.readyToAssignCategoryId, amount: 3000, cleared: .cleared),
            payee: "Arbeitgeber")
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
                approved: false, source: .bank), payee: "Netflix")
        add(
            Transaction(
                id: "WAIT", accountId: giro, date: date("2026-10-22"), categoryId: groceries, amount: -5,
                approved: false, source: .bank), payee: "Edeka")
    }

    private mutating func add(_ transaction: Transaction, payee: String? = nil) {
        try! test.budget.apply(.addTransaction(transaction, payeeName: payee))
    }

    var budget: Budget { test.budget }

    private var listed: [Transaction] {
        let starting = test.budget.transactions.first!.id
        return budget.transactions(inAccount: giro).filter { $0.id != starting }
    }

    func found(_ text: String) -> [String] {
        let search = RegisterSearch(text)
        let lookup = BudgetLookup(budget)
        return listed.filter { search.hit($0, lookup: lookup, formatter: BudgetFormatter()) != nil }.map(\.id).sorted()
    }

    func hit(_ text: String, _ id: String) -> RegisterSearch.Hit? {
        RegisterSearch(text).hit(
            budget.transaction(withId: id)!, lookup: BudgetLookup(budget), formatter: BudgetFormatter())
    }

    func shown(_ filter: RegisterFilter) -> [String] {
        let lookup = BudgetLookup(budget)
        return listed.filter { filter.includes($0, in: lookup) }.map(\.id).sorted()
    }
}

@Suite struct RegisterSearchMatchTests {
    private let fixture = SearchFixture()

    @Test func findsPayeeCategoryAndMemo() {
        #expect(fixture.found("rew") == ["REWE"])
        #expect(fixture.found("fuel") == ["ARAL"])
        #expect(fixture.found("milch") == ["REWE"])
    }

    @Test func findsReadyToAssignAsZuVerteilen() {
        #expect(fixture.found("zu vert") == ["SALARY"])
    }

    @Test func findsTheAmountWithoutSignAsTheRegisterWritesIt() {
        #expect(fixture.found("1.062,40") == ["ARAL"])
        #expect(fixture.found("62,4") == ["ARAL"])
        #expect(fixture.found("9,99") == ["BANK"])
        #expect(fixture.found("3.000,00") == ["SALARY"])
        #expect(fixture.found("-40") == [])
    }

    @Test func findsASplitByItsPartsAndSaysSo() {
        #expect(fixture.found("seife") == ["SPLIT"])
        #expect(fixture.found("household") == ["SPLIT"])
        #expect(fixture.hit("essen", "SPLIT") == .part)
        #expect(fixture.hit("kaufland", "SPLIT") == .transaction)
        #expect(fixture.hit("50,00", "SPLIT") == .transaction)
    }

    @Test func findsAPartsOwnPayee() throws {
        var fixture = SearchFixture()
        let split = Transaction(
            id: "DM", accountId: fixture.giro, date: date("2026-10-22"), categoryId: EntityID.splitCategory,
            amount: -15,
            subtransactions: [
                Subtransaction(id: "D1", transactionId: "DM", amount: -10),
                Subtransaction(id: "D2", transactionId: "DM", amount: -5),
            ])
        try fixture.test.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: split, payeeName: "Rossmann", subPayeeNames: ["D2": "dm"], isNew: true)))
        #expect(fixture.found("dm") == ["DM"])
        #expect(fixture.hit("dm", "DM") == .part)
    }

    @Test func findsTransferPayees() {
        #expect(fixture.found("Transfer : Tages") == ["SAVE"])
    }

    @Test func textWithAColonIsSearchedAsText() {
        #expect(fixture.found("Empfänger: Aral") == [])
        #expect(fixture.found("Ist: Gebucht") == [])
    }

    @Test func anEmptySearchFindsEverything() {
        #expect(fixture.found("  ").count == 7)
    }

    @Test func comparesIgnoringCaseEmojiSharpSAndHowUmlautsAreWritten() throws {
        var test = TestBudget()
        let bakery = try test.add(test.girokonto, -3, payee: "🥨 Bäckerei Straße")
        let other = try test.add(test.girokonto, -4, payee: "Edeka")
        let lookup = BudgetLookup(test.budget)
        func found(_ text: String) -> [String] {
            [bakery, other].filter { id in
                RegisterSearch(text).hit(
                    test.budget.transaction(withId: id)!, lookup: lookup, formatter: BudgetFormatter())
                    != nil
            }
        }
        #expect(found("BÄCKEREI STRASSE") == [bakery])
        #expect(found("Ba\u{308}ckerei") == [bakery])
        #expect(found("🥨 bäckerei") == [bakery])
    }

    @Test func theViewsFilterByApprovalClearedStateAndMissingCategory() throws {
        var fixture = SearchFixture()
        let uncategorized = try fixture.test.add(fixture.giro, -7, payee: "Kiosk")
        #expect(fixture.shown(.all).count == 8)
        #expect(fixture.shown(.unapproved) == ["BANK", "WAIT"].sorted())
        #expect(fixture.shown(.uncleared) == ["REWE", "SAVE", "SPLIT", "WAIT", uncategorized].sorted())
        #expect(fixture.shown(.needsCategory) == ["BANK", uncategorized].sorted())
    }

    @Test func aWaitingImportWithoutCategoryIsInBothViews() throws {
        var fixture = SearchFixture()
        try fixture.test.budget.apply(
            .addTransaction(
                Transaction(
                    id: "IMPORT", accountId: fixture.giro, date: date("2026-10-23"), amount: -3, approved: false,
                    source: .bank),
                payeeName: "Kiosk"))
        #expect(fixture.shown(.unapproved).contains("IMPORT"))
        #expect(fixture.shown(.needsCategory).contains("IMPORT"))
    }

    @Test func zuBestaetigenListsAWaitingTransferBetweenBudgetAccountsWithACategory() throws {
        var fixture = SearchFixture()
        try fixture.test.budget.apply(
            .addTransaction(
                Transaction(
                    id: "MOVE", accountId: fixture.giro, date: date("2026-10-23"), categoryId: fixture.test.groceries,
                    amount: -3, approved: false, source: .bank
                ).transferring(to: fixture.test.tagesgeld), payeeName: nil))
        #expect(fixture.budget.errorState(of: fixture.budget.transaction(withId: "MOVE")!).level == .error)
        #expect(fixture.shown(.unapproved).contains("MOVE"))
        #expect(!fixture.shown(.needsCategory).contains("MOVE"))
    }

    @Test func ohneKategorieTakesASplitByItsParts() throws {
        var fixture = SearchFixture()
        try fixture.test.budget.apply(
            .addTransaction(
                Transaction(
                    id: "PARTS", accountId: fixture.giro, date: date("2026-10-23"), categoryId: EntityID.splitCategory,
                    amount: -3,
                    subtransactions: [
                        Subtransaction(
                            id: "P1", transactionId: "PARTS", amount: -2, categoryId: fixture.test.groceries),
                        Subtransaction(id: "P2", transactionId: "PARTS", amount: -1),
                    ]), payeeName: "Markt"))
        #expect(fixture.shown(.needsCategory).contains("PARTS"))
        #expect(!fixture.shown(.needsCategory).contains("SPLIT"))
    }
}
