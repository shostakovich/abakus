import AbakusCore
import Foundation
import Observation

enum RenameTransactionsChoice: Hashable, Sendable {
    case rename, cancel
}

@MainActor
@Observable
public final class PayeeSettingsModel: Identifiable {
    public enum State: Hashable, Sendable {
        case noSelection, single, multiple
    }

    public struct Row: Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var isEnabled: Bool
        public var hasRules: Bool
        public var isSelected: Bool
    }

    public struct RuleRow: Identifiable, Hashable, Sendable {
        public var id: String
        public var `operator`: StringOperator
        public var operand: String

        public var isBlank: Bool { operand.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public enum Field: Hashable, Sendable {
        case rename, combine, category
        case operand(String)
    }

    public static let title = "Empfänger verwalten"
    public static let selectPrompt = "Empfänger zum Bearbeiten wählen"
    public static let listTooltip =
        "Aufgeführte Empfänger erscheinen in der Empfängerliste, werden beim Tippen ergänzt und automatisch "
        + "kategorisiert."
    public static let combineTooltip =
        "Fasst die ausgewählten Empfänger unter dem Namen aus „Neuer Name“ zusammen. Dazu entstehen "
        + "Umbenennungsregeln, damit künftige Buchungen automatisch umbenannt werden."
    public static let disabledTooltip =
        "Dieser Empfänger ist ausgeblendet: Er erscheint nicht in der Empfängerliste, wird beim Tippen nicht "
        + "ergänzt und nicht automatisch kategorisiert."

    public let id = UUID()
    public let dialogs: DialogStack
    @ObservationIgnored let store: any BudgetStoring
    @ObservationIgnored let today: DateWithoutTime
    @ObservationIgnored var onAutoFillChanged: (AutoFillSettings) -> Void = { _ in }
    @ObservationIgnored var onShowTransactions: (_ payeeName: String, _ showScheduled: Bool) -> Void = { _, _ in }
    @ObservationIgnored var onClose: (_ lastUsedPayeeId: String?) -> Void = { _ in }

    /// The presentation model's order: `selectedPayee` is the first.
    public private(set) var selection: [String] = []
    public private(set) var autoFill: AutoFillSettings
    public private(set) var isRenaming = false
    public var renameText = ""
    public private(set) var categoryText = ""
    public private(set) var categoryList: DropDownState?
    public private(set) var rules: [RuleRow] = []
    public var combineName = ""
    public private(set) var addCategoryForm: AddCategoryForm?
    public private(set) var focusRequest: (field: Field, token: Int)?
    public private(set) var scrollRequest: (payeeId: String, token: Int)?
    @ObservationIgnored private var requests = 0
    @ObservationIgnored private var isClosed = false

    init(
        store: any BudgetStoring, initialPayeeId: String?, autoFill: AutoFillSettings,
        dialogs: DialogStack = DialogStack()
    ) {
        self.store = store
        self.dialogs = dialogs
        self.autoFill = autoFill
        today = store.today()
        if let initialPayeeId, store.budget.payee(withId: initialPayeeId) != nil {
            setSelection([initialPayeeId])
            requestScroll(to: initialPayeeId)
        }
    }

    var budget: Budget { store.budget }
    var formatter: BudgetFormatter { BudgetFormatter(metaData: budget.budgetMetaData) }

    public var rows: [Row] {
        let selected = Set(selection)
        return budget.payeesSortedByName.map {
            Row(
                id: $0.id, name: $0.name, isEnabled: budget.isSuggested($0),
                hasRules: !budget.renameConditions(ofPayee: $0.id).isEmpty,
                isSelected: selected.contains($0.id))
        }
    }

    public var state: State {
        switch selection.count {
        case 0: .noSelection
        case 1: .single
        default: .multiple
        }
    }

    public var selectedPayee: Payee? { selection.first.flatMap(budget.payee(withId:)) }
    public var selectedPayeeName: String { selectedPayee?.name ?? "" }
    public var isTransfer: Bool { selectedPayee?.isTransferPayee ?? false }

    /// New payees come first, the one farthest from the shown payee leading, so a ⇧-click shows the clicked one.
    public func selectionChanged(to ids: Set<String>) {
        guard ids != Set(selection) else { return }
        let order = rows.map(\.id)
        let origin = selection.first.flatMap(order.firstIndex(of:)) ?? 0
        let added = order.indices.filter { ids.contains(order[$0]) && !selection.contains(order[$0]) }
            .sorted { (abs($0 - origin), $0) > (abs($1 - origin), $1) }
            .map { order[$0] }
        setSelection(added + selection.filter(ids.contains))
    }

    private func setSelection(_ ids: [String]) {
        let before = state
        let beforeFirst = selection.first
        if before == .single { flushCategory() }
        closeCategoryList()
        isRenaming = false
        selection = ids
        switch state {
        case .single where before != .single || beforeFirst != ids.first:
            loadSinglePayee()
        case .multiple where before != .multiple:
            combineName = selectedPayeeName
            requestFocus(.combine)
        default:
            break
        }
    }

    private func loadSinglePayee() {
        guard let payee = selectedPayee else { return }
        isRenaming = false
        renameText = payee.name
        categoryText = categoryDisplay(payee.lastCategoryId)
        rules = ruleRows(of: payee)
    }

    /// A rename or merge can add rules to the shown payee; blank rows still being typed stay.
    private func reloadRules() {
        guard state == .single, let payee = selectedPayee else { return }
        rules =
            ruleRows(of: payee) + rules.filter(\.isBlank)
    }

    private func ruleRows(of payee: Payee) -> [RuleRow] {
        budget.renameConditions(ofPayee: payee.id).map { RuleRow(id: $0.id, operator: $0.operator, operand: $0.text) }
    }

    private func requestFocus(_ field: Field) {
        requests += 1
        focusRequest = (field, requests)
    }

    private func requestScroll(to payeeId: String) {
        requests += 1
        scrollRequest = (payeeId, requests)
    }

    public func startRenaming() {
        guard state == .single, !isTransfer else { return }
        renameText = selectedPayeeName
        isRenaming = true
        requestFocus(.rename)
    }

    public func cancelRenaming() {
        isRenaming = false
    }

    public func saveRename() {
        guard isRenaming, let payee = selectedPayee else { return }
        isRenaming = false
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name == payee.name {
            renameText = payee.name
            return
        }
        guard perform(.renamePayee(payeeId: payee.id, name: name)) else { return }
        if let renamed = budget.payee(named: name) {
            setSelection([renamed.id])
            requestScroll(to: renamed.id)
        }
    }

    public var isSelectedPayeeEnabled: Bool { selectedPayee.map(budget.isSuggested) ?? false }

    public func setSelectedPayeeEnabled(_ enabled: Bool) {
        guard let payee = selectedPayee, !payee.isTransferPayee else { return }
        perform(.setPayeesHidden([payee.id], !enabled))
    }

    public var transactionCount: Int { selectedPayee.map { budget.payeeUseCount($0.id) } ?? 0 }

    public var transactionCountText: String {
        "\(transactionCount)" + (transactionCount == 1 ? " Buchung" : " Buchungen")
    }

    public func showTransactionsClicked() {
        guard let payee = selectedPayee else { return }
        let scheduled = budget.payeeHasScheduledTransactions(payee.id)
        close()
        onShowTransactions(payee.name, scheduled)
    }

    public var renameIfLabel: String {
        "Importierte Buchungen in <b>\(Self.escaped(selectedPayeeName))</b> umbenennen, wenn der Empfänger:"
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func categoryDisplay(_ categoryId: String?) -> String {
        guard let categoryId, categoryId != EntityID.splitCategory else { return "" }
        return budget.categoryDisplayName(categoryId)
    }

    var categoryItems: [DropDownItem] {
        DropDownCatalog(budget: budget, formatter: formatter, today: today).categoryItems(includeSplit: false).map {
            item in
            var item = item
            item.balance = nil
            return item
        }
    }

    private func showCategoryList(_ items: [DropDownItem], highlighted: Int?) {
        categoryList = DropDownState(
            field: .main(.category), kind: .category, items: items, highlighted: highlighted,
            scrollToken: (categoryList?.scrollToken ?? 0) + 1, hidesFooter: true)
    }

    public func categoryFocused() {
        guard !isClosed else { return }
        let items = categoryItems
        showCategoryList(items, highlighted: items.firstIndex { $0.isEnabled && $0.value == categoryText })
    }

    public func categoryButtonClicked() {
        if categoryList == nil { categoryFocused() } else { closeCategoryList() }
        requestFocus(.category)
    }

    public func categoryTextChanged(_ text: String) {
        guard text != categoryText else { return }
        categoryText = text
        let items = DropDownMatching.filter(categoryItems, kind: .category, text: text)
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        showCategoryList(
            items, highlighted: typed ? DropDownMatching.highlight(items, kind: .category, text: text) : nil)
    }

    public func moveCategoryHighlight(by offset: Int) {
        guard var list = categoryList else {
            categoryFocused()
            return
        }
        let enabled = list.items.indices.filter { list.items[$0].isEnabled }
        guard !enabled.isEmpty else { return }
        let position = list.highlighted.flatMap { enabled.firstIndex(of: $0) }
        let next = position.map { min(max($0 + offset, 0), enabled.count - 1) } ?? (offset > 0 ? 0 : enabled.count - 1)
        list.highlighted = enabled[next]
        list.scrollToken += 1
        categoryList = list
        categoryText = list.items[enabled[next]].value
    }

    public func categoryRowClicked(_ index: Int) {
        guard let list = categoryList, list.items.indices.contains(index), list.items[index].isEnabled else { return }
        categoryText = list.items[index].value
        commitCategory()
    }

    public func closeCategoryList() {
        categoryList = nil
    }

    /// A text naming no category is dropped instead of asking for a new one over a changing dialog.
    private func flushCategory() {
        guard categoryText != categoryDisplay(selectedPayee?.lastCategoryId) else { return }
        updateSelectedCategory(askingForNew: false)
    }

    public func categoryFocusLost() {
        guard !isClosed, categoryList != nil || categoryText != categoryDisplay(selectedPayee?.lastCategoryId)
        else { return }
        commitCategory()
    }

    public func commitCategory() {
        if let list = categoryList, let index = list.highlighted, list.items.indices.contains(index),
            !categoryText.trimmingCharacters(in: .whitespaces).isEmpty
        {
            categoryText = list.items[index].value
        }
        closeCategoryList()
        updateSelectedCategory(askingForNew: true)
    }

    private func updateSelectedCategory(askingForNew: Bool) {
        guard let payee = selectedPayee else { return }
        let typed = categoryText.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            perform(.setPayeeLastCategory(payeeId: payee.id, categoryId: nil))
            return
        }
        if let categoryId = lookUpCategory(typed) {
            perform(.setPayeeLastCategory(payeeId: payee.id, categoryId: categoryId))
            categoryText = categoryDisplay(categoryId)
            return
        }
        guard askingForNew else {
            categoryText = categoryDisplay(payee.lastCategoryId)
            return
        }
        var (master, name) = CategoryNames.components(typed)
        if typed.lowercased() == CategoryNames.addNewCategory.lowercased() {
            (master, name) = ("", "")
        } else if CategoryNames.isIncomeGroupName(master) {
            dialogs.show(
                .message(
                    TransactionEditor.otherCategoryName, BudgetError.categoryCantBeIncome.errorDescription ?? ""))
            return
        } else if CategoryNames.isReservedGroupName(master) {
            master = ""
        }
        addCategoryForm = AddCategoryForm(masterName: master, name: name)
    }

    private func lookUpCategory(_ typed: String) -> String? {
        budget.incomeCategory(label: typed) ?? budget.category(fullName: typed)?.id
    }

    public var masterCategoryNames: [String] { budget.budgetCategoryGroups.map(\.name) }

    public func addCategoryConfirmed(masterName: String, name: String) {
        guard var form = addCategoryForm, let payee = selectedPayee else { return }
        do {
            try store.perform(.addNamedCategory(groupName: masterName, name: name))
        } catch {
            form.masterName = masterName
            form.name = name
            addCategoryForm = form
            let message = TaskDialog<MessageChoice>.message(
                TransactionEditor.otherCategoryName, error.localizedDescription)
            dialogs.show(message) { [weak self] in self?.addCategoryForm?.refocusRequest += 1 }
            return
        }
        addCategoryForm = nil
        let fullName =
            masterName.trimmingCharacters(in: .whitespaces) + ": " + name.trimmingCharacters(in: .whitespaces)
        guard let added = budget.category(fullName: fullName)?.id else { return }
        perform(.setPayeeLastCategory(payeeId: payee.id, categoryId: added))
        categoryText = categoryDisplay(added)
    }

    var addCategoryRequest: AddCategoryRequest? {
        addCategoryForm.map {
            AddCategoryRequest(
                form: $0, masterNames: masterCategoryNames, onCreate: addCategoryConfirmed,
                onCancel: addCategoryCancelled)
        }
    }

    public func addCategoryCancelled() {
        addCategoryForm = nil
        categoryText = categoryDisplay(selectedPayee?.lastCategoryId)
    }

    public func addRuleClicked() {
        let rule = RuleRow(id: EntityID.createUID(), operator: .contains, operand: "")
        rules.append(rule)
        commitRules()
        requestFocus(.operand(rule.id))
    }

    public func removeRule(_ ruleId: String) {
        rules.removeAll { $0.id == ruleId }
        commitRules()
    }

    public func setOperator(_ ruleId: String, _ op: StringOperator) {
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        rules[index].operator = op
        commitRules()
    }

    public func setOperand(_ ruleId: String, _ operand: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        rules[index].operand = operand
        commitRules()
    }

    public func isLastRule(_ ruleId: String) -> Bool { rules.last?.id == ruleId }

    public var canRenameExisting: Bool { rules.last.map { !$0.isBlank } ?? false }

    private func commitRules() {
        guard let payee = selectedPayee else { return }
        let conditions = rules.map { PayeeRenameCondition(id: $0.id, operator: $0.operator, text: $0.operand) }
        perform(.setPayeeRenameConditions(payeeId: payee.id, conditions))
    }

    public func renameExistingClicked() {
        guard let payee = selectedPayee, canRenameExisting else { return }
        let preview = budget.renameRulePreview(for: payee.id)
        guard preview.transactionCount > 0 else {
            dialogs.show(
                TaskDialog<MessageChoice>(
                    instruction: "Keine Buchungen zum Umbenennen gefunden.",
                    content: "Diese Regeln treffen auf keinen Empfänger einer Buchung zu.",
                    buttons: [.init(.close, title: "OK", isDefault: true)], dismissal: .close))
            return
        }
        let name = Self.escaped(payee.name)
        let instruction =
            preview.transactionCount == 1
            ? "Bei 1 Buchung wird der Empfänger in „\(name)“ umbenannt:"
            : "Bei \(preview.transactionCount) Buchungen wird der Empfänger in „\(name)“ umbenannt:"
        let names = preview.payeeNames.map { "„\(Self.escaped($0))“" }.joined(separator: ", ")
        let payeeId = payee.id
        dialogs.ask(
            TaskDialog<RenameTransactionsChoice>(
                title: "Buchungen umbenennen?", instruction: instruction,
                content: "<b>Betroffene Empfänger:</b> " + names,
                buttons: [
                    .init(.rename, title: "Umbenennen", isDefault: true), .init(.cancel, title: "Abbrechen"),
                ],
                dismissal: .cancel)
        ) { [weak self] answer in
            if answer.choice == .rename { self?.perform(.applyRenameRules(payeeId: payeeId)) }
        }
    }

    public var multipleTitle: String { "\(selection.count) Empfänger ausgewählt" }

    /// The last selected name comes first.
    public var selectedNamesText: String {
        selection.reversed().compactMap { budget.payee(withId: $0)?.name }.map { "„\($0)“" }.joined(separator: ", ")
    }

    public var canCombine: Bool { !combineName.trimmingCharacters(in: .whitespaces).isEmpty }

    public func combineClicked() {
        let name = combineName.trimmingCharacters(in: .whitespaces)
        guard canCombine else { return }
        let renamable = selection.filter { budget.payee(withId: $0)?.isTransferPayee == false }
        guard perform(.combinePayees(selection, name: name)), !renamable.isEmpty,
            let combined = budget.payee(named: name)
        else { return }
        setSelection([combined.id])
        requestScroll(to: combined.id)
    }

    public func setSelectedPayeesEnabled(_ enabled: Bool) {
        perform(.setPayeesHidden(selection, !enabled))
    }

    public func setAutoFill(_ settings: AutoFillSettings) {
        autoFill = settings
        onAutoFillChanged(settings)
    }

    public func close() {
        if state == .single { flushCategory() }
        closeCategoryList()
        isClosed = true
        onClose(selection.first)
    }

    /// Escape: the category drop-down first, then the dialog without storing the last used payee.
    public func escapePressed() {
        if categoryList != nil {
            closeCategoryList()
        } else {
            isClosed = true
            onClose(nil)
        }
    }

    @discardableResult
    private func perform(_ command: BudgetCommand) -> Bool {
        do {
            try store.perform(command)
            if case .setPayeeRenameConditions = command {} else { reloadRules() }
            return true
        } catch let error as BudgetError {
            dialogs.show(.message(error.dialogInstruction, error.dialogContent ?? ""))
            return false
        } catch {
            dialogs.show(.message("Abakus", error.localizedDescription))
            return false
        }
    }
}

extension PayeeSettingsModel: DropDownListHost {
    func dropDownRowHovered(_ index: Int?) {
        guard var list = categoryList else { return }
        if let index, list.items.indices.contains(index), !list.items[index].isEnabled { return }
        list.highlighted = index
        categoryList = list
    }

    func dropDownRowClicked(_ index: Int) {
        categoryRowClicked(index)
    }

    func dropDownFooterClicked() {}
}
