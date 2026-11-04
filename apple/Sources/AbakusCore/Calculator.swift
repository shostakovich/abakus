import Foundation

public struct Calculator: Hashable, Sendable {
    public enum Operator: String, Hashable, Sendable, CaseIterable {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
    }

    public enum Key: Hashable, Sendable {
        case digit(Int)
        case point
        case op(Operator)
        case equals
        case clear
        case negate
        case backspace
    }

    public static let maxDisplayLength = 30

    public private(set) var display: String
    public private(set) var isError = false
    private var register: Decimal
    private var pendingOperator: Operator?
    private var isNewValue = true
    private let formatter: BudgetFormatter
    private let errorText: String

    public init(value: Decimal, operator: Operator?, formatter: BudgetFormatter, errorText: String = "Fehler") {
        self.formatter = formatter
        self.errorText = errorText
        register = value
        pendingOperator = `operator`
        display = formatter.currencySimple(value)
    }

    public mutating func press(_ key: Key) {
        if key == .clear {
            register = 0
            display = formatter.currencySimple(0)
            isNewValue = true
            isError = false
            return
        }
        guard !isError else { return }
        switch key {
        case .backspace:
            guard !isNewValue else { return }
            display.removeLast(display.isEmpty ? 0 : 1)
            if display.isEmpty { display = "0" }
        case .negate:
            let minus = BudgetFormatter.minus
            display = display.hasPrefix(minus) ? String(display.dropFirst()) : minus + display
            if isNewValue { register = -register }
        case .digit(let digit):
            enter(String(digit))
        case .point:
            let separator = formatter.currencyLocale.decimalSeparator
            guard isNewValue || !display.contains(separator) else { return }
            enter(separator)
        case .op(let op):
            evaluate()
            pendingOperator = op
        case .equals:
            evaluate()
            pendingOperator = nil
        case .clear:
            break
        }
    }

    /// OK / Enter: `=` then the display read with either decimal separator.
    public mutating func result() -> Decimal {
        press(.equals)
        return formatter.parseAmountWithUnknownDecimalSeparator(display)
    }

    private mutating func enter(_ text: String) {
        guard display.count < Self.maxDisplayLength else { return }
        display = isNewValue ? text : display + text
        isNewValue = false
    }

    private mutating func evaluate() {
        guard !isNewValue else { return }
        let operand = formatter.parseAmountUnrounded(display)
        register = calculate(register, operand)
        isNewValue = true
    }

    private mutating func calculate(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        let value: Decimal
        switch pendingOperator {
        case .add: value = lhs + rhs
        case .subtract: value = lhs - rhs
        case .multiply: value = lhs * rhs
        case .divide: value = lhs == 0 && rhs == 0 ? 0 : lhs / rhs
        case nil: value = rhs
        }
        let rounded = Amount.round(value, digits: 12)
        if rounded.isNaN || !rounded.isFinite {
            display = errorText
            isError = true
        } else {
            display = formatter.currencySimple(rounded)
        }
        return rounded
    }
}

extension Calculator.Key {
    public static func typed(_ character: String, decimalSeparator: String) -> Calculator.Key? {
        let upper = character.uppercased()
        if let digit = Int(upper), (0...9).contains(digit) { return .digit(digit) }
        if upper == "." || upper == "," || upper == decimalSeparator { return .point }
        if let op = Calculator.Operator(rawValue: upper) { return .op(op) }
        switch upper {
        case "=": return .equals
        case "C": return .clear
        case "F": return .negate
        default: return nil
        }
    }
}

extension Calculator {
    static let typedOperators: [Character: Operator] = [
        "+": .add, "-": .subtract, "−": .subtract, "*": .multiply, "×": .multiply, "/": .divide, "÷": .divide,
    ]

    /// Left to right as the calculator works; nil without an operator between two numbers or on division by zero.
    public static func evaluate(_ expression: String, formatter: BudgetFormatter) -> Decimal? {
        var operands = [""]
        var operators: [Operator] = []
        for character in expression {
            let operand = operands[operands.count - 1]
            if let op = typedOperators[character], operand.contains(where: \.isNumber) {
                operators.append(op)
                operands.append("")
            } else {
                operands[operands.count - 1].append(character)
            }
        }
        if operands.count > 1, !operands[operands.count - 1].contains(where: \.isNumber) {
            operands.removeLast()
            operators.removeLast()
        }
        guard !operators.isEmpty else { return nil }
        var value = formatter.parseAmountUnrounded(operands[0])
        for (op, operand) in zip(operators, operands.dropFirst()) {
            let rhs = formatter.parseAmountUnrounded(operand)
            switch op {
            case .add: value += rhs
            case .subtract: value -= rhs
            case .multiply: value *= rhs
            case .divide:
                guard rhs != 0 else { return nil }
                value /= rhs
            }
        }
        return Amount.round(value, digits: formatter.currencyLocale.decimalDigits)
    }
}
