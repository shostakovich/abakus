import AbakusCore
import Foundation

extension TransactionEditor {
    @discardableResult
    public func handleKey(_ key: EditorKey) -> Bool {
        guard !hasOpenDialog else { return true }
        if calculator != nil { return calculatorKey(key) }
        switch focus {
        case .button(let button): return buttonKey(key, button)
        case .field(let field): return fieldKey(key, field)
        case nil: return false
        }
    }

    private func buttonKey(_ key: EditorKey, _ button: EditorButton) -> Bool {
        switch key {
        case .tab, .backTab:
            showsButtonFocus = true
            setFocus(neighbor(of: .button(button), backward: key == .backTab), commitCurrent: true)
        case .enter, .space:
            activate(button)
        case .escape:
            cancel()
        default:
            return false
        }
        return true
    }

    private func fieldKey(_ key: EditorKey, _ field: EditorFieldID) -> Bool {
        if let dropDown, dropDown.field == field, let handled = listKey(key, field, dropDown) { return handled }
        if field.column == .date, dateKey(key) { return true }
        if field.column == .frequency, frequencyKey(key) { return true }
        if field.column.isAmount, amountKey(key, field) { return true }
        switch key {
        case .down where dropDownKind(for: field) != nil:
            showDropDown(for: field, unfiltered: true)
        case .tab, .backTab:
            showsButtonFocus = true
            if let next = neighbor(of: .field(field), backward: key == .backTab) {
                setFocus(next, commitCurrent: true)
            }
        case .enter:
            if isCalendarOpen { isCalendarOpen = false }
            activate(defaultButton)
        case .escape:
            if isCalendarOpen {
                isCalendarOpen = false
            } else {
                resetEditedField(field)
            }
        default:
            return false
        }
        return true
    }

    /// While the list is open; nil lets the key through.
    private func listKey(_ key: EditorKey, _ field: EditorFieldID, _ list: DropDownState) -> Bool? {
        switch key {
        case .down: moveHighlight(by: 1)
        case .up: moveHighlight(by: -1)
        case .pageDown: moveHighlight(by: list.kind.rowCount)
        case .pageUp: moveHighlight(by: -list.kind.rowCount)
        case .escape: dropDown = nil
        case .backspace:
            dropDown = nil
            let current = text(field) as NSString
            let anchor = min(fieldSelection.location, current.length)
            let kept = fieldSelection.length > 0 ? anchor : max(0, anchor - 1)
            setText(field, current.substring(to: kept))
            select(field, NSRange(location: kept, length: 0))
        case .enter:
            if list.highlightedItem != nil {
                acceptHighlighted(field, backward: false)
            } else {
                dropDown = nil
            }
        case .tab, .backTab:
            guard list.highlightedItem != nil else {
                dropDown = nil
                return nil
            }
            acceptHighlighted(field, backward: false)
        default:
            return nil
        }
        return true
    }

    private func dateKey(_ key: EditorKey) -> Bool {
        let separator = formatter.dateLocale.dateSeparator
        let base = clone.date
        let target: DateWithoutTime
        var opensCalendar = true
        switch key {
        case .down: target = base.addingDays(-1)
        case .up: target = base.addingDays(1)
        case .escape where isCalendarOpen:
            isCalendarOpen = false
            return true
        case .character(let character):
            switch character {
            case "-" where separator != "-": target = base.addingDays(-1)
            case "+", "=": target = base.addingDays(1)
            case "t", "T":
                target = today
                opensCalendar = false
            case "." where separator != ".":
                target = today
                opensCalendar = false
            case "m": target = base.firstOfMonth
            case "M", "h", "H": target = base.lastOfMonth
            case "y": target = DateWithoutTime(year: base.year, month: 1, day: 1)
            case "Y", "r", "R": target = DateWithoutTime(year: base.year, month: 12, day: 31)
            default: return false
            }
        default:
            return false
        }
        chooseDate(target)
        if opensCalendar { isCalendarOpen = true }
        return true
    }

    private func amountKey(_ key: EditorKey, _ field: EditorFieldID) -> Bool {
        guard case .character(let character) = key else { return false }
        let value = formatter.parseAmount(text(field))
        let op: Calculator.Operator
        switch character {
        case "+": op = .add
        case "*": op = .multiply
        case "/": op = .divide
        case "-" where value != 0: op = .subtract
        default: return false
        }
        calculator = EditorCalculator(
            field: field, calculator: Calculator(value: value, operator: op, formatter: formatter))
        return true
    }

    public func openCalculator(for field: EditorFieldID) {
        guard field.column.isAmount, !isLocked(field) else { return }
        if focus != .field(field) { fieldClicked(field) }
        calculator = EditorCalculator(
            field: field,
            calculator: Calculator(value: formatter.parseAmount(text(field)), operator: nil, formatter: formatter))
    }

    private func calculatorKey(_ key: EditorKey) -> Bool {
        switch key {
        case .enter: calculatorOK()
        case .escape: calculator = nil
        case .backspace: calculatorPress(.backspace)
        case .character(let character):
            if let typed = Calculator.Key.typed(character, decimalSeparator: formatter.currencyLocale.decimalSeparator)
            {
                calculatorPress(typed)
            }
        default:
            break
        }
        return true
    }

    public func calculatorPress(_ key: Calculator.Key) {
        calculator?.calculator.press(key)
    }

    /// The result goes into the field as plain amount text; the field commits as usual later.
    public func calculatorOK() {
        guard var state = calculator else { return }
        let result = state.calculator.result()
        calculator = nil
        setText(state.field, formatter.currencySimple(result))
        if focus != .field(state.field) { setFocus(.field(state.field), commitCurrent: true) }
        selectAll(state.field)
    }

    public func calculatorCancel() {
        calculator = nil
    }

    public func toggleCalendar() {
        guard !isLocked(.main(.date)) else { return }
        if focus != .field(.main(.date)) { fieldClicked(.main(.date)) }
        isCalendarOpen.toggle()
    }

    /// The date picker's month arrows step the date by a month and keep it open; a picked day closes it.
    public func calendarDatePicked(_ date: DateWithoutTime) {
        let isMonthStep = date == clone.date.addingMonths(1) || date == clone.date.addingMonths(-1)
        if !chooseDate(date) || !isMonthStep { isCalendarOpen = false }
    }

    /// False when the date is refused as a typed one would be.
    @discardableResult
    func chooseDate(_ date: DateWithoutTime) -> Bool {
        let field = EditorFieldID.main(.date)
        if let refusal = dateRefusal(date, shownAs: formatter.dateShort(date)) {
            rejectDate(refusal)
            return false
        }
        setText(field, formatter.dateShort(date))
        clone.date = date
        dateCallout = nil
        if focus == .field(field) { selectAll(field) }
        return true
    }

    /// A changed field is restored, an unchanged one cancels the edit.
    func resetEditedField(_ field: EditorFieldID) {
        let source = original
        let restored = originalText(field, of: source)
        guard !textMatchesOriginal(field, restored) else {
            cancel()
            return
        }
        setText(field, restored)
        restoreClone(field)
        selectAll(field)
    }

    private func textMatchesOriginal(_ field: EditorFieldID, _ restored: String) -> Bool {
        let current = text(field)
        switch field.column {
        case .outflow, .inflow: return formatter.parseAmount(current) == formatter.parseAmount(restored)
        case .date: return formatter.parseDate(current, today: today) == formatter.parseDate(restored, today: today)
        default:
            return current.trimmingCharacters(in: .whitespaces).lowercased()
                == restored.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    private func restoreClone(_ field: EditorFieldID) {
        if let subId = field.subId {
            guard let index = clone.subtransactions.firstIndex(where: { $0.id == subId }) else { return }
            let old = original.subtransactions.first { $0.id == subId }
            switch field.column {
            case .payee:
                clone.subtransactions[index].payeeId = old?.payeeId
                subPayeeNames[subId] = nil
            case .category: clone.subtransactions[index].categoryId = old?.categoryId
            case .memo: clone.subtransactions[index].memo = old?.memo
            case .outflow, .inflow:
                clone.subtransactions[index].amount = old?.amount ?? 0
                refreshAmountTexts(subId: subId)
            default: break
            }
            return
        }
        switch field.column {
        case .account: clone.accountId = original.accountId
        case .date: clone.date = original.date
        case .payee:
            payeeName = originalPayeeName
            clone.payeeId = original.payeeId
        case .category:
            clone.categoryId = original.categoryId
            if original.isSplit != isSplitMode { setSplitMode(original.isSplit) }
        case .memo: clone.memo = original.memo
        case .outflow, .inflow:
            clone.amount = original.amount
            refreshAmountTexts(subId: nil)
        case .frequency: setFrequency(originalFrequency)
        }
    }
}
