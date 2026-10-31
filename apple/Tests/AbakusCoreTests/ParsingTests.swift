import Foundation
import Testing

@testable import AbakusCore

@Suite struct DateParsingTests {
    let german = BudgetFormatter()
    let american = BudgetFormatter(currencyLocale: .enUS)

    @Test func patternFollowsTheLocale() {
        #expect(german.shortDatePattern == "TT.MM.JJ")
        #expect(american.shortDatePattern == "MM/TT/JJ")
    }

    @Test func separatedDatesFollowTheLocaleSequence() {
        #expect(german.parseDate("05.10.26", today: october23) == date("2026-10-05"))
        #expect(american.parseDate("10/05/26", today: october23) == date("2026-10-05"))
        #expect(german.parseDate("5-10-2026", today: october23) == date("2026-10-05"))
        #expect(german.parseDate("5'10'26", today: october23) == date("2026-10-05"))
        #expect(german.parseDate(" 5 / 10 / 26 ", today: october23) == date("2026-10-05"))
    }

    @Test func missingYearIsThisYear() {
        #expect(german.parseDate("24.12", today: october23) == date("2026-12-24"))
        #expect(german.parseDate("3.", today: october23) == date("2026-01-03"))
    }

    @Test func digitsWithoutSeparatorsNeedSixOrEightDigits() {
        #expect(german.parseDate("051026", today: october23) == date("2026-10-05"))
        #expect(german.parseDate("05102026", today: october23) == date("2026-10-05"))
        #expect(german.parseDate("5102026", today: october23) == nil)
        #expect(german.parseDate("0510", today: october23) == nil)
    }

    @Test func twoDigitYearsPivotAtSeventy() {
        #expect(german.parseDate("01.01.70", today: october23)?.year == 2070)
        #expect(german.parseDate("01.01.71", today: october23)?.year == 1971)
    }

    @Test func invalidPartsAreRejected() {
        #expect(german.parseDate("", today: october23) == nil)
        #expect(german.parseDate("heute", today: october23) == nil)
        #expect(german.parseDate("01.13.26", today: october23) == nil)
        #expect(german.parseDate("32.01.26", today: october23) == nil)
        #expect(german.parseDate("a.b.c", today: october23) == nil)
        #expect(german.parseDate("05", today: october23) == nil)
    }

    @Test func overflowingDaysRollOverLikeAS3Dates() {
        #expect(german.parseDate("31.02.26", today: october23) == date("2026-03-03"))
    }

    @Test func textAfterASpaceInTheYearIsDropped() {
        #expect(german.parseDate("05.10.26 abends", today: october23) == date("2026-10-05"))
    }
}

@Suite struct AmountParsingTests {
    let german = BudgetFormatter()
    let american = BudgetFormatter(currencyLocale: .enUS)

    @Test func localeSeparatorsAreUnderstood() {
        #expect(german.parseAmount("1.234,56") == decimal("1234.56"))
        #expect(american.parseAmount("1,234.56") == decimal("1234.56"))
        #expect(german.parseAmount("12,5") == decimal("12.5"))
    }

    @Test func thousandsSeparatorIsIgnoredWhereverItIs() {
        #expect(german.parseAmount("12.50") == 1250)
    }

    @Test func currencySymbolsAndSpacesAreStripped() {
        #expect(german.parseAmount("1 234,50€") == decimal("1234.5"))
        #expect(american.parseAmount("$12.00") == 12)
    }

    @Test func minusMakesItNegative() {
        #expect(german.parseAmount("-12,30") == decimal("-12.3"))
        #expect(german.parseAmount("- 5") == -5)
    }

    @Test func textWithoutNumberIsZero() {
        #expect(german.parseAmount("abc") == 0)
        #expect(german.parseAmount("") == 0)
        #expect(german.parseAmount("-") == 0)
    }

    @Test func balancesWithoutAValidNumberAreReportedInsteadOfBecomingZero() {
        for text in ["abc", "", "-", "12abc", "1,2,3", "1 2 x", "€", ","] {
            #expect(german.parseBalance(text) == nil, "\(text)")
        }
        #expect(german.parseBalance("1.234,50 €") == decimal("1234.5"))
        #expect(german.parseBalance("-20") == -20)
        #expect(german.parseBalance("0") == 0)
        #expect(german.parseBalance("-0") == 0)
        #expect(american.parseBalance("$1,234.50") == decimal("1234.5"))
        #expect(InvalidBalance.instruction == "Ungültiger Saldo")
        #expect(InvalidBalance.content("abc") == "„abc“ ist keine gültige Zahl.")
        #expect(InvalidBalance.content("abc", bold: true) == "„<b>abc</b>“ ist keine gültige Zahl.")
    }

    @Test func amountsAreRoundedToTheCurrencyDigits() {
        #expect(german.parseAmount("1,005") == decimal("1.01"))
        #expect(german.parseAmount("1,2,3") == 0)
    }

    @Test func unknownDecimalSeparatorTakesTheLastOne() {
        #expect(german.parseAmountWithUnknownDecimalSeparator("1.234.5") == decimal("1234.5"))
        #expect(german.parseAmountWithUnknownDecimalSeparator("12.5") == decimal("12.5"))
        #expect(american.parseAmountWithUnknownDecimalSeparator("12,5") == decimal("12.5"))
    }
}

@Suite struct CalculatorTests {
    let formatter = BudgetFormatter()

    func calculator(_ value: Decimal, _ op: Calculator.Operator?) -> Calculator {
        Calculator(value: value, operator: op, formatter: formatter)
    }

    @Test func startsWithTheFieldValueAndTheTypedOperator() {
        var calculator = calculator(10, .add)
        #expect(calculator.display == "10,00")
        calculator.press(.digit(5))
        #expect(calculator.display == "5")
        #expect(calculator.result() == 15)
        #expect(calculator.display == "15,00")
    }

    @Test func chainsOperators() {
        var calculator = calculator(100, .subtract)
        calculator.press(.digit(2))
        calculator.press(.digit(0))
        calculator.press(.op(.multiply))
        #expect(calculator.display == "80,00")
        calculator.press(.digit(2))
        #expect(calculator.result() == 160)
    }

    @Test func decimalPointUsesTheLocaleSeparator() {
        var calculator = calculator(0, .add)
        calculator.press(.digit(1))
        calculator.press(.point)
        calculator.press(.digit(5))
        #expect(calculator.display == "1,5")
        #expect(calculator.result() == decimal("1.5"))
    }

    @Test func divisionByZeroShowsTheErrorAndGivesZero() {
        var calculator = calculator(10, .divide)
        calculator.press(.digit(0))
        #expect(calculator.result() == 0)
        #expect(calculator.display == "Fehler")
    }

    @Test func zeroDividedByANumberIsZero() {
        var calculator = calculator(0, .divide)
        calculator.press(.digit(5))
        #expect(calculator.result() == 0)
        #expect(calculator.display == "0,00")
    }

    @Test func backspaceNegateAndClear() {
        var calculator = calculator(0, nil)
        calculator.press(.digit(4))
        calculator.press(.digit(2))
        calculator.press(.backspace)
        #expect(calculator.display == "4")
        calculator.press(.negate)
        #expect(calculator.display == "-4")
        calculator.press(.backspace)
        calculator.press(.backspace)
        #expect(calculator.display == "0")
        calculator.press(.clear)
        #expect(calculator.display == "0,00")
    }

    @Test func editingAShownResultAndASecondSeparatorStayInStep() {
        var negated = calculator(10, .add)
        negated.press(.digit(5))
        negated.press(.equals)
        negated.press(.negate)
        #expect(negated.display == "-15,00")
        negated.press(.op(.add))
        negated.press(.digit(3))
        #expect(negated.result() == -12)

        var shown = calculator(10, .add)
        shown.press(.digit(5))
        shown.press(.equals)
        shown.press(.backspace)
        #expect(shown.display == "15,00")
        #expect(shown.result() == 15)

        var decimals = calculator(0, nil)
        for key: Calculator.Key in [.digit(1), .point, .digit(5), .point, .digit(2)] { decimals.press(key) }
        #expect(decimals.display == "1,52")
        #expect(decimals.result() == decimal("1.52"))
    }

    @Test func displayIsLimitedToThirtyCharacters() {
        var calculator = calculator(0, nil)
        for _ in 0..<40 { calculator.press(.digit(1)) }
        #expect(calculator.display.count == 30)
    }
}

@Suite struct BudgetAmountParsingTests {
    let german = BudgetFormatter()

    @Test func emptyTextIsZeroAndTypedNumbersAreRead() {
        #expect(german.parseBudgetAmount("") == 0)
        #expect(german.parseBudgetAmount(" ") == 0)
        #expect(german.parseBudgetAmount("12,5") == 12.5)
        #expect(german.parseBudgetAmount("12.5") == 125)
        #expect(german.parseBudgetAmount("1.234,50€") == 1234.5)
        #expect(german.parseBudgetAmount("-5") == -5)
        #expect(german.parseBudgetAmount("10(5") == 5)
    }

    @Test func textWithoutANumberIsNotAnAmount() {
        #expect(german.parseBudgetAmount("1,2,3") == nil)
        #expect(german.parseBudgetAmount("-") == nil)
        #expect(german.parseBudgetAmount("+/") == nil)
    }

    @Test func aNumberTooLargeForDecimalIsNotAnAmount() {
        #expect(german.parseBudgetAmount(String(repeating: "9", count: 165))?.isFinite == true)
        #expect(german.parseBudgetAmount(String(repeating: "9", count: 166)) == nil)
        #expect(german.parseBudgetAmount(",") == 0)
    }
}
