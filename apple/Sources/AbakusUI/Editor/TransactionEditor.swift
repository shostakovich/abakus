import AbakusCore
import Foundation
import Observation

public enum EditorOutcome: Hashable, Sendable {
    case cancelled
    case saved(transactionId: String, addAnother: Bool, findNext: Bool, incomeCheck: Bool)
    case deleteRequested(transactionId: String)
}

/// One edited register row: it edits a clone that Done/Save copies back through `store.perform`.
@MainActor
@Observable
public final class TransactionEditor {
    public let mode: EditorMode
    public let isAllAccounts: Bool
    @ObservationIgnored let store: any BudgetStoring
    @ObservationIgnored let today: DateWithoutTime
    public let dialogs: DialogStack
    @ObservationIgnored var onFinish: (EditorOutcome) -> Void = { _ in }
    @ObservationIgnored var onEditPayees: (String?) -> Void = { _ in }
    @ObservationIgnored var autoFillSettings = AutoFillSettings()
    /// The transaction being edited; for a new one the defaults it started with.
    public internal(set) var original: Transaction
    let originalPayeeName: String
    let originalErrorLevel: ErrorLevel
    let needsApproval: Bool
    /// Amount, date, account and payee follow the leader's source and stay as they are.
    public let leader: TransactionLeader?

    public internal(set) var clone: Transaction
    public internal(set) var payeeName: String
    public internal(set) var columns: [RegisterColumn]
    public internal(set) var texts: [EditorFieldID: String] = [:]
    public internal(set) var focus: EditorFocus?
    public internal(set) var selectionRequest: EditorSelection?
    public internal(set) var dropDown: DropDownState?
    public internal(set) var isSplitMode = false
    public internal(set) var subIds: [String] = []
    /// The amount fields set to inflow, by split line id (nil for the transaction's own); the text has no sign.
    public internal(set) var inflowAmounts: Set<String?> = []
    /// Signs set by hand, which the income default leaves alone.
    var chosenSigns: Set<String?> = []
    /// Payees committed in split lines, by line id; the budget resolves them on save.
    var subPayeeNames: [String: String] = [:]
    public internal(set) var categoryPrompts: [String?: String] = [:]
    public internal(set) var dateCallout: EditorDateCallout?
    public internal(set) var calculator: EditorCalculator?
    public internal(set) var isCalendarOpen = false
    public internal(set) var glowCount = 0
    /// Flex draws the focus rectangle only after keyboard navigation.
    public internal(set) var showsButtonFocus = false
    public internal(set) var addCategoryForm: AddCategoryForm?
    public internal(set) var frequency: ScheduledTransactionFrequency?
    let originalFrequency: ScheduledTransactionFrequency?
    public internal(set) var isFrequencyListOpen = false

    var fieldSelection = NSRange(location: 0, length: 0)
    var blockNextSave = false
    var stashedSubtransactions: [Subtransaction] = []
    var pendingSave: PendingSave?
    var pendingCategoryField: EditorFieldID?
    var refocusRequest: EditorFieldID?
    private var selectionGeneration = 0

    struct PendingSave {
        var addAnother: Bool
        var findNext: Bool
        var reconciledConfirmed: Bool?
        var payeeRename: PayeeRename?
    }

    public init(
        store: any BudgetStoring, transaction: Transaction, mode: EditorMode, columns: [RegisterColumn],
        isAllAccounts: Bool, today: DateWithoutTime = .today(), frequency: ScheduledTransactionFrequency? = nil,
        dialogs: DialogStack = DialogStack()
    ) {
        self.store = store
        self.dialogs = dialogs
        self.frequency = frequency
        originalFrequency = frequency
        self.mode = mode
        self.columns = columns
        self.isAllAccounts = isAllAccounts
        self.today = today
        var editable = transaction
        if transaction.isSplit { editable.categoryId = EntityID.splitCategory }
        original = editable
        clone = editable
        let budget = store.budget
        originalPayeeName = budget.payeeName(of: transaction)
        payeeName = originalPayeeName
        originalErrorLevel = mode == .existing && frequency == nil ? budget.errorState(of: transaction).level : .none
        needsApproval = transaction.needsApproval
        leader = mode == .existing && frequency == nil ? budget.leader(of: transaction.id) : nil
        if transaction.isSplit {
            isSplitMode = true
            subIds = transaction.subtransactions.map(\.id)
        }
        resetTexts()
        categoryPrompts[nil] = initialCategoryPrompt()
        for id in subIds { categoryPrompts[id] = subCategoryPrompt(id) }
    }

    var budget: Budget { store.budget }
    var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }
    var catalog: DropDownCatalog { DropDownCatalog(budget: budget, formatter: formatter, today: today) }

    public var transactionId: String { original.id }
    public var isScheduled: Bool { originalFrequency != nil }
    public var account: Account? { budget.account(withId: clone.accountId) }
    public var isOnBudget: Bool { account?.onBudget ?? true }

    public func text(_ field: EditorFieldID) -> String { texts[field] ?? "" }

    public func isLocked(_ field: EditorFieldID) -> Bool {
        leader != nil && !field.isSub && [.account, .date, .payee, .amount].contains(field.column)
    }

    public var lockReason: String? { leader?.leadsNote }

    public func prompt(_ field: EditorFieldID) -> String {
        switch field.column {
        case .account, .date, .frequency: ""
        case .payee: "Empfänger"
        case .category: categoryPrompts[field.subId] ?? Self.categoryPrompt
        case .memo: "Memo"
        case .amount: "Betrag"
        }
    }

    public func isInflow(_ field: EditorFieldID) -> Bool { inflowAmounts.contains(field.subId) }

    func setSign(_ field: EditorFieldID, inflow: Bool) {
        if inflow { inflowAmounts.insert(field.subId) } else { inflowAmounts.remove(field.subId) }
    }

    func chooseSign(_ field: EditorFieldID, inflow: Bool) {
        chosenSigns.insert(field.subId)
        setSign(field, inflow: inflow)
    }

    func amount(of subId: String?) -> Decimal {
        guard let subId else { return clone.amount }
        return clone.subtransactions.first { $0.id == subId }?.amount ?? 0
    }

    func resetTexts() {
        for column in EditorColumn.allCases { texts[.main(column)] = originalText(.main(column), of: clone) }
        texts[.main(.payee)] = payeeName
        setSign(.main(.amount), inflow: clone.amount > 0)
        for id in subIds { resetSubTexts(id) }
    }

    func resetSubTexts(_ id: String) {
        let sub = clone.subtransactions.first { $0.id == id }
        for column in [EditorColumn.category, .memo, .amount] {
            texts[.sub(id, column)] = subText(column, of: sub)
        }
        texts[.sub(id, .payee)] = sub.map(subPayeeText) ?? ""
        resetSubSign(id)
    }

    /// A line without an amount takes the sign of what is left to split.
    func resetSubSign(_ id: String) {
        chosenSigns.remove(id)
        let amount = amount(of: id)
        setSign(.sub(id, .amount), inflow: amount == 0 ? remainingAmount > 0 : amount > 0)
    }

    func subPayeeText(_ sub: Subtransaction) -> String {
        subPayeeNames[sub.id] ?? budget.payeeName(of: sub)
    }

    func originalText(_ field: EditorFieldID, of transaction: Transaction) -> String {
        if let subId = field.subId {
            return subText(field.column, of: transaction.subtransactions.first { $0.id == subId })
        }
        let formatter = formatter
        switch field.column {
        case .account: return budget.account(withId: transaction.accountId)?.name ?? ""
        case .date: return formatter.dateShort(transaction.date)
        case .frequency: return originalFrequency?.readableName ?? ""
        case .payee: return originalPayeeName
        case .category: return categoryText(transaction.categoryId)
        case .memo: return transaction.memo ?? ""
        case .amount: return formatter.registerAmount(abs(transaction.amount))
        }
    }

    func subText(_ column: EditorColumn, of sub: Subtransaction?) -> String {
        guard let sub else { return "" }
        switch column {
        case .payee: return budget.payeeName(of: sub)
        case .category: return categoryText(sub.categoryId)
        case .memo: return sub.memo ?? ""
        case .amount: return formatter.registerAmount(abs(sub.amount))
        default: return ""
        }
    }

    func categoryText(_ categoryId: String?) -> String {
        guard isOnBudget || categoryId != nil else { return "" }
        return budget.categoryDisplayName(categoryId)
    }

    func initialCategoryPrompt() -> String {
        if originalErrorLevel == .needsCategory && isOnBudget && !original.isSplit && original.amount != 0 {
            return RegisterRowBuilder.needsCategoryPrompt
        }
        return Self.categoryPrompt
    }

    func subCategoryPrompt(_ id: String) -> String {
        guard let sub = clone.subtransactions.first(where: { $0.id == id }) else { return Self.categoryPrompt }
        if budget.errorState(of: sub, inAccount: clone.accountId).level == .needsCategory {
            return RegisterRowBuilder.needsCategoryPrompt
        }
        return Self.categoryPrompt
    }

    static let categoryPrompt = "Kategorie"
    static let categoryNotNeeded = "(Keine Kategorie nötig)"

    public var buttons: [EditorButton] {
        if mode == .new { return [.saveAndAddAnother, .save, .cancel] }
        guard needsApproval else { return [.done, .cancel] }
        guard leader == nil else { return [.approveAndFindNext, .approve, .cancel] }
        return [.approveAndFindNext, .approve, .delete, .cancel]
    }

    public var rowHeight: CGFloat {
        EditRowMetrics.height(subRows: isSplitMode ? subIds.count : nil)
    }

    /// The focused part's y-range in the edit row; the field band's starts at the row's top.
    var focusedRange: Range<CGFloat>? {
        let band = EditRowMetrics.padding + EditRowMetrics.fieldBandHeight
        switch focus {
        case nil:
            return nil
        case .button:
            return rowHeight - EditRowMetrics.padding - EditRowMetrics.buttonRowHeight..<rowHeight
        case .field(let field):
            guard let subId = field.subId else { return 0..<band }
            guard let line = subIds.firstIndex(of: subId) else { return nil }
            let top = band + CGFloat(line) * EditRowMetrics.subRowHeight
            return top..<top + EditRowMetrics.subRowHeight
        }
    }

    public var defaultButton: EditorButton { buttons[0] }

    /// The prominent button; a new transaction shows Save, while Return keeps saving and adding another.
    public var prominentButton: EditorButton { mode == .new ? .save : defaultButton }

    public func mainColumns() -> [EditorColumn] {
        EditorColumn.allCases.filter { columns.contains($0.gridColumn) }
    }

    public func subColumns() -> [EditorColumn] {
        [.payee, .category, .memo, .amount].filter { columns.contains($0.gridColumn) }
    }

    public var tabOrder: [EditorFocus] {
        var order = mainColumns().map { EditorFieldID.main($0) }.filter { !isLocked($0) }.map(EditorFocus.field)
        if isSplitMode {
            for id in subIds { order += subColumns().map { EditorFocus.field(.sub(id, $0)) } }
        }
        return order + buttons.map(EditorFocus.button)
    }

    func neighbor(of focus: EditorFocus, backward: Bool) -> EditorFocus? {
        let order = tabOrder
        guard !order.isEmpty else { return nil }
        guard let index = order.firstIndex(of: focus) else { return order.first }
        return order[(index + (backward ? order.count - 1 : 1)) % order.count]
    }

    func isIncome(categoryOf subId: String?) -> Bool {
        let categoryId =
            subId.map { id in clone.subtransactions.first { $0.id == id }?.categoryId } ?? clone.categoryId
        return budget.isReadyToAssign(categoryId)
    }

    public var focusedField: EditorFieldID? { focus?.field }

    public var hasOpenDialog: Bool { addCategoryForm != nil || dialogs.isPresenting }

    /// Another component's dialog does not hold back a save, so quitting still commits the edit.
    var hasOwnDialog: Bool { addCategoryForm != nil || dialogs.isPresenting(ownedBy: self) }

    /// Programmatic focus moves (Tab, commits): the field that loses focus has been committed already.
    func setFocus(_ requested: EditorFocus?, commitCurrent: Bool) {
        var target = requested
        if let field = target?.field, isLocked(field) { target = tabOrder.first }
        if let current = focus, current != target {
            closePopups()
            if commitCurrent, let field = current.field { blur(field) }
        }
        if let refocus = refocusRequest {
            refocusRequest = nil
            target = .field(refocus)
        }
        guard focus != target else { return }
        focus = target
        if let field = target?.field { didFocus(field) }
    }

    public func fieldClicked(_ field: EditorFieldID) {
        guard focus != .field(field), !isLocked(field) else { return }
        setFocus(.field(field), commitCurrent: true)
    }

    /// AppKit ended editing without the editor moving focus (another control took it).
    public func fieldDidLoseFocus(_ field: EditorFieldID) {
        guard focus == .field(field), !hasOpenDialog else { return }
        closePopups()
        blur(field)
        refocusRequest = nil
        if focus == .field(field) { focus = nil }
    }

    /// Focus-out: a highlighted list row is taken, then the field commits.
    func blur(_ field: EditorFieldID) {
        if let dropDown, dropDown.field == field {
            if let item = dropDown.highlightedItem {
                setText(field, item.value)
                _ = commit(field, reason: .clickedItem(backward: false))
            }
            self.dropDown = nil
        }
        _ = commit(field, reason: .lostFocus)
    }

    func didFocus(_ field: EditorFieldID) {
        if field == .main(.date) && text(field).isEmpty { texts[field] = formatter.dateShort(today) }
        if field.column == .amount && amount(of: field.subId) == 0 && !chosenSigns.contains(field.subId)
            && isIncome(categoryOf: field.subId)
        {
            setSign(field, inflow: true)
        }
        selectAll(field)
        switch field.column {
        case .category: showDropDown(for: field, unfiltered: true)
        case .account: showDropDown(for: field, unfiltered: true)
        default: break
        }
    }

    func selectAll(_ field: EditorFieldID) {
        select(field, NSRange(location: 0, length: (text(field) as NSString).length))
    }

    func select(_ field: EditorFieldID, _ range: NSRange) {
        selectionGeneration += 1
        fieldSelection = range
        selectionRequest = EditorSelection(field: field, range: range, generation: selectionGeneration)
    }

    func setText(_ field: EditorFieldID, _ value: String) {
        texts[field] = value
    }

    func moveFocus(after field: EditorFieldID, backward: Bool) {
        guard let next = neighbor(of: .field(field), backward: backward) else { return }
        setFocus(next, commitCurrent: false)
    }

    public var hasOpenPopup: Bool {
        dropDown != nil || calculator != nil || isCalendarOpen || isFrequencyListOpen
    }

    func closePopups() {
        dropDown = nil
        calculator = nil
        isCalendarOpen = false
        isFrequencyListOpen = false
    }

    public func textDidChange(_ field: EditorFieldID, text newText: String, selection: NSRange, isDeletion: Bool) {
        texts[field] = newText
        fieldSelection = selection
        if dateCallout != nil && field == .main(.date) { dateCallout = nil }
        guard let kind = dropDownKind(for: field) else { return }
        autoComplete(field, kind: kind, isDeletion: isDeletion)
    }

    public func selectionDidChange(_ field: EditorFieldID, selection: NSRange) {
        guard focus == .field(field) else { return }
        fieldSelection = selection
    }

    /// The fields a click outside protects with the glow.
    public var hasChanges: Bool {
        clone.date != original.date
            || payeeName.trimmingCharacters(in: .whitespaces).lowercased()
                != originalPayeeName.trimmingCharacters(in: .whitespaces).lowercased()
            || clone.categoryId != original.categoryId || (clone.memo ?? "") != (original.memo ?? "")
            || clone.amount != original.amount || frequency != originalFrequency
            || clone.accountId != original.accountId || clone.subtransactions != original.subtransactions
            || subPayeeNames.contains { id, name in
                original.subtransactions.first { $0.id == id }
                    .map { !Payee.sameName(name, budget.payeeName(of: $0)) } ?? true
            }
    }

    /// A click outside the row: with changes it is swallowed and the button row glows, without it cancels.
    public func clickedOutside() -> Bool {
        guard !hasOpenDialog else { return true }
        if let field = focus?.field {
            closePopups()
            _ = commit(field, reason: .lostFocus)
            refocusRequest = nil
        }
        if hasChanges {
            glowCount += 1
            return true
        }
        cancel()
        return false
    }

    public func cancel() {
        closePopups()
        addCategoryForm = nil
        dialogs.dismiss(ownedBy: self)
        onFinish(.cancelled)
    }

    public func menuAction(_ action: RegisterMenuAction) {
        switch action {
        case .frequency(let frequency): frequencyChosen(frequency)
        default: break
        }
    }

    /// Writes a stored transaction at once, so Cancel keeps it.
    public func toggleCleared() {
        guard mode == .existing, !isScheduled else {
            switch clone.cleared {
            case .cleared: clone.cleared = .uncleared
            case .uncleared:
                clone.cleared = .cleared
                clone.approved = true
            case .reconciled: break
            }
            return
        }
        do {
            try store.perform(.toggleCleared([transactionId]))
        } catch {
            showMessage(.message(error.localizedDescription, ""), refocus: nil)
            return
        }
        guard let stored = budget.transaction(withId: transactionId) else { return }
        original.cleared = stored.cleared
        original.approved = stored.approved
        clone.cleared = stored.cleared
        clone.approved = clone.approved || stored.approved
    }
}

public struct DropDownState: Hashable, Sendable {
    public var field: EditorFieldID
    public var kind: DropDownKind
    public var items: [DropDownItem]
    public var highlighted: Int?
    public var scrollToken = 0
    public var hidesFooter = false

    public var footerTitle: String? { hidesFooter ? nil : kind.footerTitle }

    public var highlightedItem: DropDownItem? { highlighted.flatMap { items.indices.contains($0) ? items[$0] : nil } }
}
