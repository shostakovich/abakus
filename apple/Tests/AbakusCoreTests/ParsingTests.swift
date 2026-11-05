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

    @Test func shownAmountsReadBack() {
        let shown = german.currency(decimal("-1234.5"))
        #expect(german.parseAmount(shown) == decimal("-1234.5"))
        #expect(german.parseBalance(shown) == decimal("-1234.5"))
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
}

@Suite struct AmountExpressionTests {
    let german = BudgetFormatter()
    let american = BudgetFormatter(currencyLocale: .enUS)

    func evaluate(_ text: String) -> Decimal? {
        Calculator.evaluate(text, formatter: german)
    }

    @Test func plusAndMinusAreWorkedLeftToRight() {
        #expect(evaluate("50+20") == 70)
        #expect(evaluate("10-5") == 5)
        #expect(evaluate("10−5−8") == -3)
        #expect(evaluate("12,50 + 7,30") == decimal("19.8"))
        #expect(evaluate("1.000,00€+2") == 1002)
        #expect(Calculator.evaluate("1,000.50+0.5", formatter: american) == 1001)
    }

    @Test func aLeadingSignBelongsToTheFirstNumber() {
        #expect(evaluate("-50+20") == -30)
        #expect(evaluate("−5−3") == -8)
        #expect(evaluate("+5−8") == -3)
        #expect(evaluate("-12,50") == decimal("-12.5"))
    }

    @Test func aPlainNumberIsItsValue() {
        #expect(evaluate("12,50") == decimal("12.5"))
        #expect(evaluate(",5") == decimal("0.5"))
        #expect(evaluate("12,") == 12)
        #expect(evaluate("1,500") == decimal("1.5"))
        #expect(evaluate("1,230") == decimal("1.23"))
    }

    @Test func aDotIsADecimalSeparatorUnlessExactlyThreeDigitsFollowIt() {
        #expect(evaluate("12.50") == decimal("12.5"))
        #expect(evaluate("12.5") == decimal("12.5"))
        #expect(evaluate("1.500") == 1500)
        #expect(evaluate(".500") == decimal("0.5"))
        #expect(evaluate("1.234.567") == 1_234_567)
        #expect(evaluate("1,234,567") == 1_234_567)
        #expect(evaluate("1.234,5") == decimal("1234.5"))
        #expect(evaluate("1,234.5") == decimal("1234.5"))
        #expect(evaluate("12.50+1.000") == decimal("1012.5"))
    }

    @Test func moreDecimalsThanTheCurrencyHasAreRejected() {
        for text in ["1,005", "0.125", "1,2345"] {
            #expect(evaluate(text) == nil, "\(text)")
        }
    }

    @Test func otherOperatorsAndUnreadableTextAreRejected() {
        for text in [
            "60*2", "10/2", "5×2", "10÷2", "12,50+", "5+-3", "+", "-", "", " ", "abc", "1,2,3", "10(5", "1.23.4",
            "12.34.5", "1.2,3", "1,2.345,6", ".", ",",
        ] {
            #expect(evaluate(text) == nil, "\(text)")
        }
    }

    @Test func moreThanFifteenIntegerDigitsArePerPartOrInTotalRejected() {
        let largest = String(repeating: "9", count: 15)
        #expect(evaluate(largest) == Decimal(string: largest))
        #expect(evaluate("-" + largest + ",99") == -(Decimal(string: largest)! + decimal("0.99")))
        #expect(evaluate("1" + largest) == nil)
        #expect(evaluate("0" + largest) == nil)
        #expect(evaluate("999.999.999.999.999.999") == nil)
        #expect(evaluate(largest + "+1") == nil)
        #expect(evaluate("-" + largest + "-1") == nil)
        #expect(evaluate(largest + "+1-1") == Decimal(string: largest))
    }
}
