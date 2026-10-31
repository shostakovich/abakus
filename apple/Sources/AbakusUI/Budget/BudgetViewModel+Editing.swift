import AbakusCore
import CoreGraphics
import Foundation

public struct BudgetCellID: Hashable, Sendable {
    public let month: DateWithoutTime
    public let categoryId: String

    public init(month: DateWithoutTime, categoryId: String) {
        self.month = month.firstOfMonth
        self.categoryId = categoryId
    }
}

public struct BudgetCellEdit: Hashable, Sendable {
    public let cell: BudgetCellID
    public internal(set) var text: String
    public internal(set) var selectAllRequest = 0
}

public struct BudgetQuickBudgetList: Hashable, Sendable {
    public static let calculatorLabel = "Rechner zeigen"
    public static let rowHeight = SystemChrome.menuRowHeight
    public static let separatorHeight: CGFloat = 11
    static let labelFont = ThemeFont.body
    static let amountFont = ThemeFont(size: ThemeFont.body.size, hasTabularDigits: true)
    static let iconWidth: CGFloat = 16
    static let iconGap: CGFloat = 6
    static let gap: CGFloat = 12
    static let inset = 10 + SystemChrome.menuPadding

    static func label(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    public let cell: BudgetCellID
    public let options: [QuickBudgetOption]
    public let width: CGFloat
    public internal(set) var highlighted = 0

    public var rowCount: Int { options.count + 1 }
    public var height: CGFloat {
        2 * SystemChrome.menuPadding + CGFloat(rowCount) * Self.rowHeight + Self.separatorHeight
    }
}

public struct BudgetCalculator: Hashable, Sendable {
    public let cell: BudgetCellID
    public internal(set) var calculator: Calculator
}

public enum BudgetCellKey: Hashable, Sendable {
    case tab, backTab, enter, up, down, escape, pageUp, pageDown, f2, backspace
    case character(String)
}

extension BudgetViewModel {
    public func assignedText(_ cell: BudgetCellID) -> String {
        let assigned = month(cell.month)?.category(cell.categoryId)?.assigned ?? 0
        return assigned == 0 ? "" : formatter.currencyNoSymbol(assigned)
    }

    public func beginEdit(_ cell: BudgetCellID) {
        guard editor?.cell != cell else { return }
        commitEdit()
        calculator = nil
        guard shownMonths.contains(cell.month), groups.editableCategoryIds.contains(cell.categoryId) else { return }
        editor = BudgetCellEdit(cell: cell, text: assignedText(cell), selectAllRequest: 1)
        reveal(cell.categoryId)
    }

    public func cellTextChanged(_ text: String) {
        editor?.text = text
    }

    /// Text that does not parse keeps the stored amount.
    public func commitEdit() {
        guard let edit = editor else { return }
        editor = nil
        quickBudget = nil
        store(edit.text, in: edit.cell)
    }

    public func cancelEdit() {
        editor = nil
        quickBudget = nil
    }

    private func store(_ text: String, in cell: BudgetCellID) {
        guard let amount = formatter.parseBudgetAmount(text) else { return }
        setAssigned(amount, in: cell)
    }

    private func setAssigned(_ amount: Decimal, in cell: BudgetCellID) {
        guard amount != month(cell.month)?.category(cell.categoryId)?.assigned else { return }
        try? store.perform(.setAssigned(month: cell.month, categoryId: cell.categoryId, amount: amount))
    }

    @discardableResult
    public func cellKey(_ key: BudgetCellKey) -> Bool {
        guard let edit = editor else { return false }
        if quickBudget != nil { return quickBudgetKey(key) }
        switch key {
        case .tab, .enter, .down: moveEdit(from: edit.cell, forward: true)
        case .backTab, .up: moveEdit(from: edit.cell, forward: false)
        case .escape: cancelEdit()
        case .pageUp, .pageDown: pageScroll(down: key == .pageDown)
        case .f2: openQuickBudget()
        case .backspace: return false
        case .character(let character): return cellCharacter(character, edit)
        }
        return true
    }

    private func cellCharacter(_ character: String, _ edit: BudgetCellEdit) -> Bool {
        switch character {
        case "+": openCalculator(.add)
        case "*": openCalculator(.multiply)
        case "/": openCalculator(.divide)
        case "-" where formatter.parseAmount(edit.text) != 0: openCalculator(.subtract)
        default: return false
        }
        return true
    }

    /// Everything up to "/" passes, so signs and the calculator's operators can be typed.
    public static func allowsTyping(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return scalar.value <= 0x2F || ("0"..."9").contains(character) || character == "[" || character == "]"
    }

    private func moveEdit(from cell: BudgetCellID, forward: Bool) {
        let order = groups.editableCategoryIds
        guard let index = order.firstIndex(of: cell.categoryId) else { return }
        let next = order[(index + (forward ? 1 : order.count - 1)) % order.count]
        guard next != cell.categoryId else {
            commitEdit()
            beginEdit(cell)
            return
        }
        beginEdit(BudgetCellID(month: cell.month, categoryId: next))
    }

    public func dropDownButtonClicked() {
        if quickBudget != nil {
            quickBudget = nil
        } else {
            openQuickBudget()
        }
    }

    public func openQuickBudget() {
        guard let edit = editor else { return }
        let options = sheet.quickBudgetOptions(categoryId: edit.cell.categoryId, month: edit.cell.month)
        quickBudget = BudgetQuickBudgetList(cell: edit.cell, options: options, width: quickBudgetWidth(options))
    }

    /// Wide enough for the longest row, so no label is cut.
    func quickBudgetWidth(_ options: [QuickBudgetOption]) -> CGFloat {
        let list = BudgetQuickBudgetList.self
        let rows = options.map {
            list.labelFont.width(of: list.label($0.label))
                + list.amountFont.width(of: formatter.currencyNoSymbol($0.amount))
        }
        let calculator = list.iconWidth + list.iconGap + list.labelFont.width(of: list.calculatorLabel)
        return (rows + [calculator]).max(by: <)! + list.gap + 2 * list.inset
    }

    public func quickBudgetRowHovered(_ index: Int) {
        quickBudget?.highlighted = index
    }

    private func quickBudgetKey(_ key: BudgetCellKey) -> Bool {
        guard let list = quickBudget else { return false }
        switch key {
        case .up: quickBudget?.highlighted = max(0, list.highlighted - 1)
        case .down: quickBudget?.highlighted = min(list.rowCount - 1, list.highlighted + 1)
        case .enter: quickBudgetChosen(list.highlighted)
        case .escape: quickBudget = nil
        case .character("+"): openCalculator(.add)
        case .character("*"): openCalculator(.multiply)
        case .character("/"): openCalculator(.divide)
        default: break
        }
        return true
    }

    public func quickBudgetChosen(_ index: Int) {
        guard let list = quickBudget, var edit = editor else { return }
        guard list.options.indices.contains(index) else {
            openCalculator(nil)
            return
        }
        quickBudget = nil
        let amount = list.options[index].amount
        setAssigned(amount, in: list.cell)
        edit.text = formatter.currencyNoSymbol(month(list.cell.month)?.category(list.cell.categoryId)?.assigned ?? 0)
        edit.selectAllRequest += 1
        editor = edit
    }

    /// The field gives its focus to the calculator, so its text is stored first.
    public func openCalculator(_ operator: Calculator.Operator?) {
        guard let edit = editor else { return }
        let value = formatter.parseAmount(edit.text)
        commitEdit()
        calculator = BudgetCalculator(
            cell: edit.cell, calculator: Calculator(value: value, operator: `operator`, formatter: formatter))
        panelFocusRequest += 1
    }

    public func calculatorPress(_ key: Calculator.Key) {
        calculator?.calculator.press(key)
    }

    /// An "Error" result stays on the display.
    public func calculatorOK() {
        guard let state = calculator else { return }
        var evaluated = state.calculator
        let result = evaluated.result()
        guard !evaluated.isError else {
            calculator?.calculator = evaluated
            return
        }
        calculator = nil
        setAssigned(result, in: state.cell)
        beginEdit(state.cell)
    }

    public func calculatorCancel() {
        calculator = nil
    }

    @discardableResult
    public func calculatorKey(_ key: BudgetCellKey) -> Bool {
        guard calculator != nil else { return false }
        switch key {
        case .enter: calculatorOK()
        case .escape: calculatorCancel()
        case .backspace: calculatorPress(.backspace)
        case .character(let character):
            if let typed = Calculator.Key.typed(character, decimalSeparator: formatter.currencyLocale.decimalSeparator)
            {
                calculatorPress(typed)
            }
        default: break
        }
        return true
    }

    public func panelKey(_ key: BudgetCellKey) -> Bool {
        if calculator != nil { return calculatorKey(key) }
        switch key {
        case .pageUp, .pageDown:
            pageScroll(down: key == .pageDown)
            return true
        default:
            return false
        }
    }

    public func mouseDownOutsideEditedRow() {
        commitEdit()
    }

    public func mouseDownOutsideQuickBudget() {
        quickBudget = nil
    }

    public func mouseDownOutsideCalculator() {
        calculator = nil
    }
}
