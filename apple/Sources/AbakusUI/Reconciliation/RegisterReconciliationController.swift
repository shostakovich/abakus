import AbakusCore
import Foundation
import Observation

/// The register's "reconcile" state of one account; it lasts for the session.
struct RegisterReconciliation {
    var statementDate: DateWithoutTime
    var statementBalance: Decimal
    var savedSearchText: String
    var savedSearchFilter: RegisterSearchFilter?
    var savedDateFilter: DateFilterSelection?
    var savedExpandedSplitsBeforeSearch: Set<String>?
    var savedScrollBeforeSearch: RegisterScrollRequest.Target?
    var savedSort: RegisterSortOrder
    var savedSchedulerVisible: Bool
}

@MainActor
@Observable
public final class ReconciliationStatementForm: Identifiable {
    public static let title = "Konto abgleichen"
    public static let intro = "Gib den Saldo aus dem Onlinebanking oder vom Kontoauszug ein, um abzugleichen."
    public static let dateQuestion = "Zu welchem Datum abgleichen?"
    public static let balanceQuestion = "Wie viel hatte das Konto an dem Tag laut Bank?"

    public let id = UUID()
    public let accountId: String
    public let isContinuing: Bool
    public var date: DateWithoutTime
    /// Typed but not yet committed: clicking a button does not end the date field's editing.
    public var typedDate: String?
    public var amountText: String

    init(accountId: String, isContinuing: Bool, date: DateWithoutTime, amountText: String) {
        self.accountId = accountId
        self.isContinuing = isContinuing
        self.date = date
        self.amountText = amountText
    }

    public var beginTitle: String { isContinuing ? "Übernehmen" : "Weiter" }
    public var canBegin: Bool { !amountText.isEmpty }
}

/// The summary reads as an equation: last cleared + cleared above = cleared balance − statement balance.
public enum ReconciliationOperation: String, Hashable, Sendable {
    case plus = "+"
    case equals = "="
    case minus = "\u{2212}"
}

public struct ReconciliationFooterRow: Hashable, Sendable {
    public var label: String
    public var value: String
    public var operation: ReconciliationOperation?
}

public enum ReconciliationAction: CaseIterable, Hashable, Sendable {
    case stop, adjust, finish

    public var title: String {
        switch self {
        case .stop: ReconciliationFooterModel.stopTitle
        case .adjust: ReconciliationFooterModel.adjustTitle
        case .finish: ReconciliationFooterModel.finishTitle
        }
    }
}

public struct ReconciliationFooterModel: Hashable, Sendable {
    public static let pendingText = "Markiere Buchungen oben als gebucht,\nbis die Salden übereinstimmen"
    public static let doneText = "Die Salden stimmen überein.\nDas Konto ist jetzt abgeglichen"
    public static let finishTitle = "Abgleichen"
    public static let adjustTitle = "Banksaldo ändern"
    public static let stopTitle = "Abgleich abbrechen"
    public static let differenceTitle = "Differenz zur Bank"

    public var rows: [ReconciliationFooterRow]
    public var difference: String
    public var isBalanced: Bool

    public var message: String { isBalanced ? Self.doneText : Self.pendingText }
}

enum UnbalancedChoice: Hashable, Sendable {
    case createAdjustment, continueReconciling
}

@MainActor
@Observable
public final class RegisterReconciliationController {
    public static let reconcileHelpText =
        "In „Alle Konten“ lässt sich nicht abgleichen.<br/>Wähle zuerst das Konto, das du abgleichen willst."

    static let unbalancedDialog = TaskDialog<UnbalancedChoice>(
        instruction: "Die Salden stimmen nicht überein.",
        content: "Eine Ausgleichsbuchung über die Differenz gleicht den Saldo an die Bank an.",
        buttons: [
            .init(.createAdjustment, title: "Ausgleichen und abgleichen"),
            .init(.continueReconciling, title: "Weiter abgleichen", isDefault: true),
        ],
        dismissal: .continueReconciling)

    unowned let register: RegisterViewModel
    public internal(set) var statementForm: ReconciliationStatementForm?
    public internal(set) var showsReconcileHelp = false

    init(register: RegisterViewModel) {
        self.register = register
    }

    var current: RegisterReconciliation? { register.viewState.reconciliation }

    public var isReconcileEnabled: Bool { !register.isAllAccounts && register.account != nil }

    /// Only Alle Konten explains the disabled button.
    public var reconcileTooltip: String? {
        register.isAllAccounts ? "Wähle in der Seitenleiste ein Konto zum Abgleichen." : nil
    }

    public func reconcileClicked() {
        guard let account = register.account, statementForm == nil, !register.clickedOutsideEditors() else { return }
        statementForm = ReconciliationStatementForm(
            accountId: account.id, isContinuing: false, date: register.today(), amountText: "")
    }

    public func statementHint(_ form: ReconciliationStatementForm) -> String {
        let cleared = register.store.budget.balances(forAccount: form.accountId, through: form.date).cleared
        return "Gebuchter Saldo bis dahin: \(register.formatter.currency(cleared))."
    }

    public func statementCancelled() {
        statementForm = nil
    }

    public func commitStatementDate(_ form: ReconciliationStatementForm) {
        guard let text = form.typedDate else { return }
        if let date = register.formatter.parseDate(text, today: register.today()) { form.date = date }
        form.typedDate = nil
    }

    /// The hint's link: the cleared balance as the statement balance, and go.
    public func useClearedBalance(_ form: ReconciliationStatementForm) {
        commitStatementDate(form)
        let cleared = register.store.budget.balances(forAccount: form.accountId, through: form.date).cleared
        form.amountText = register.formatter.currencyNoSymbol(cleared)
        begin(form)
    }

    public func begin(_ form: ReconciliationStatementForm) {
        commitStatementDate(form)
        guard form.canBegin, register.accountKey == form.accountId else { return }
        guard let balance = register.formatter.parseBalance(form.amountText) else {
            register.dialogs.show(.invalidBalance(form.amountText))
            return
        }
        statementForm = nil
        var state = register.viewState
        if var running = state.reconciliation {
            running.statementDate = form.date
            running.statementBalance = balance
            register.viewState.reconciliation = running
            return
        }
        register.cancelEdits()
        register.schedulerHidden()
        register.closeOverlays()
        state.reconciliation = RegisterReconciliation(
            statementDate: form.date, statementBalance: balance, savedSearchText: state.searchText,
            savedSearchFilter: state.searchFilter, savedDateFilter: state.dateFilter,
            savedExpandedSplitsBeforeSearch: state.expandedSplitsBeforeSearch,
            savedScrollBeforeSearch: state.scrollBeforeSearch, savedSort: state.sort,
            savedSchedulerVisible: state.isSchedulerVisible)
        state.searchText = ""
        state.searchFilter = nil
        state.dateFilter = nil
        state.expandedSplitsBeforeSearch = nil
        state.scrollBeforeSearch = nil
        state.sort = .default
        state.isSchedulerVisible = false
        register.viewState = state
        register.clearSelection()
    }

    public var footer: ReconciliationFooterModel? {
        guard let reconciliation = current, let account = register.account else { return nil }
        let summary = reconciliationSummary(reconciliation)
        let formatter = register.formatter
        let date = formatter.dateShort(reconciliation.statementDate)
        let lastText =
            account.lastReconciledOn.map { "Abgeglichener Saldo vom " + formatter.dateShort($0) }
            ?? "Noch nie abgeglichen"
        return ReconciliationFooterModel(
            rows: [
                ReconciliationFooterRow(
                    label: lastText, value: formatter.currency(summary.reconciledBalance), operation: nil),
                ReconciliationFooterRow(
                    label: "Oben als gebucht markiert", value: formatter.currency(summary.clearedAbove),
                    operation: .plus),
                ReconciliationFooterRow(
                    label: "Gebuchter Saldo am " + date, value: formatter.currency(summary.clearedBalance),
                    operation: .equals),
                ReconciliationFooterRow(
                    label: "Banksaldo am " + date, value: formatter.currency(summary.statementBalance),
                    operation: .minus),
            ],
            difference: formatter.currency(summary.difference), isBalanced: summary.isBalanced)
    }

    private func reconciliationSummary(_ reconciliation: RegisterReconciliation) -> ReconciliationSummary {
        register.store.budget.reconciliationSummary(
            accountId: register.accountKey ?? "", statementBalance: reconciliation.statementBalance,
            list: register.transactions)
    }

    public func perform(_ action: ReconciliationAction) {
        switch action {
        case .stop: stopReconcilingClicked()
        case .adjust: adjustStatementClicked()
        case .finish: finishReconciliationClicked()
        }
    }

    public func finishReconciliationClicked() {
        guard let reconciliation = current else { return }
        if reconciliationSummary(reconciliation).isBalanced {
            finishReconciliation(createsAdjustment: false)
        } else {
            register.dialogs.ask(Self.unbalancedDialog) { [weak self] answer in
                if answer.choice == .createAdjustment { self?.finishReconciliation(createsAdjustment: true) }
            }
        }
    }

    public func adjustStatementClicked() {
        guard let reconciliation = current, let key = register.accountKey else { return }
        statementForm = ReconciliationStatementForm(
            accountId: key, isContinuing: true, date: reconciliation.statementDate,
            amountText: register.formatter.currencySimple(reconciliation.statementBalance))
    }

    public func stopReconcilingClicked() {
        leaveReconciliation()
    }

    private func finishReconciliation(createsAdjustment: Bool) {
        guard let reconciliation = current, let key = register.accountKey else { return }
        let finish = ReconciliationFinish(
            accountId: key, statementDate: reconciliation.statementDate,
            statementBalance: reconciliation.statementBalance, transactionIds: register.transactionIds,
            createsAdjustment: createsAdjustment, today: register.today())
        register.cancelEdits()
        guard register.perform(.finishReconciliation(finish)) else { return }
        leaveReconciliation()
    }

    private func leaveReconciliation() {
        var state = register.viewState
        guard let saved = state.reconciliation else { return }
        register.closeOverlays()
        if state.searchFilter != nil, let splits = state.expandedSplitsBeforeSearch { state.expandedSplits = splits }
        state.reconciliation = nil
        state.searchText = saved.savedSearchText
        state.searchFilter = saved.savedSearchFilter
        state.dateFilter = saved.savedDateFilter
        state.expandedSplitsBeforeSearch = saved.savedExpandedSplitsBeforeSearch
        state.scrollBeforeSearch = saved.savedScrollBeforeSearch
        state.sort = saved.savedSort
        state.isSchedulerVisible = saved.savedSchedulerVisible
        register.viewState = state
        register.clearSelection()
    }

    /// Mouse-down on the disabled button points at the Budget Accounts list.
    public func reconcileDisabledClicked() {
        guard !isReconcileEnabled else { return }
        showsReconcileHelp = true
    }

    public func reconcileHelpDismissed() {
        showsReconcileHelp = false
    }
}
