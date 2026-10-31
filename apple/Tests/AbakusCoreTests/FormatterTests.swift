import Testing

@testable import AbakusCore

@Suite struct FormatterTests {
    let german = BudgetFormatter(currencyLocale: .deDE)
    let american = BudgetFormatter(currencyLocale: .enUS)

    @Test func germanCurrencyHasTheSymbolOnTheRightWithoutSpace() {
        #expect(german.currency(decimal("1234.5")) == "1.234,50€")
        #expect(german.currency(decimal("-1234.5")) == "-1.234,50€")
        #expect(german.currency(0) == "0,00€")
    }

    @Test func americanCurrencyPutsTheMinusBeforeTheSymbol() {
        #expect(american.currency(decimal("1234.5")) == "$1,234.50")
        #expect(american.currency(decimal("-1234.5")) == "-$1,234.50")
    }

    @Test func noSymbolKeepsThousands() {
        #expect(german.currencyNoSymbol(decimal("1234567.891")) == "1.234.567,89")
        #expect(american.currencyNoSymbol(decimal("-1234.5")) == "-1,234.50")
        #expect(german.currencyNoSymbol(decimal("999.999")) == "1.000,00")
    }

    @Test func simpleDropsThousands() {
        #expect(german.currencySimple(decimal("-1234.5")) == "-1234,50")
    }

    @Test func registerCellsAreEmptyForZero() {
        #expect(german.registerAmount(0) == "")
        #expect(german.registerAmount(decimal("0.004")) == "")
        #expect(german.registerAmount(decimal("12")) == "12,00")
    }

    @Test func tinyNegativeAmountsAreNotNegativeZero() {
        #expect(german.currency(decimal("-0.004")) == "0,00€")
    }

    @Test func shortDatesFollowTheDateLocale() {
        #expect(german.dateShort(october23) == "23.10.26")
        #expect(american.dateShort(october23) == "10/23/26")
    }

    @Test func monthNamesComeFromTheDateLocale() {
        #expect(german.monthName(10) == "Oktober")
        #expect(american.monthName(3) == "March")
        #expect(german.monthHeader(october23) == "Oktober 2026")
    }

    @Test func incomeReadsZuVerteilen() {
        let budget = Budget(budgetName: "Test")
        #expect(budget.categoryDisplayName(budget.readyToAssignCategoryId) == "Zu verteilen")
        #expect(Budget(budgetName: "Test", categoryGroups: []).incomeCategory(label: " zu VERTEILEN ") != nil)
    }

    @Test func otherCategoriesUseMasterAndSubName() {
        let fixture = TestBudget()
        #expect(fixture.budget.categoryDisplayName(fixture.groceries) == "Everyday Expenses: Groceries")
        #expect(fixture.budget.categoryDisplayName(EntityID.splitCategory) == "Aufteilung")
        #expect(fixture.budget.categoryDisplayName(nil) == "")
    }

    @Test func metaDataSelectsTheLocales() {
        let formatter = BudgetFormatter(metaData: BudgetMetaData(currencyLocale: "en_US", dateLocale: "de_DE"))
        #expect(formatter.currency(1) == "$1.00")
        #expect(formatter.dateShort(october23) == "23.10.26")
    }

    @Test func otherLocalesAreDerivedFromFoundation() {
        let locale = FormatLocale(identifier: "fr_FR")
        #expect(locale.decimalSeparator == ",")
        #expect(locale.monthNames.count == 12)
        #expect(locale.dateSequence == .dmy)
    }
}
