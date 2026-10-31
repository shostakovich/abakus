import Foundation

public enum Amount {
    /// Halves round towards +infinity (-2.505 becomes -2.50).
    public static func round(_ value: Decimal, digits: Int = 2) -> Decimal {
        var shifted = value + halfUnit(digits: digits)
        var result = Decimal()
        NSDecimalRound(&result, &shifted, digits, .down)
        return result.isZero ? 0 : result
    }

    public static func sum<S: Sequence>(_ values: S, digits: Int = 2) -> Decimal where S.Element == Decimal {
        values.reduce(Decimal(0)) { round($0 + $1, digits: digits) }
    }

    private static func halfUnit(digits: Int) -> Decimal {
        Decimal(sign: .plus, exponent: -(digits + 1), significand: 5)
    }
}
