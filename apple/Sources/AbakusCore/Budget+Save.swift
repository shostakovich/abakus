import Foundation

public struct PayeeRename: Hashable, Sendable {
    public enum Choice: Hashable, Sendable {
        case rename
        case renameAndCategorize
        case leave
    }

    public var choice: Choice
    /// "Don't try to bulk-rename this payee again" disables the old payee.
    public var stopAsking: Bool

    public init(choice: Choice, stopAsking: Bool = false) {
        self.choice = choice
        self.stopAsking = stopAsking
    }
}

public enum PayeeRenameCheck: Hashable, Sendable {
    case renameSilently
    case ask(oldName: String, newName: String, matches: Int, uncategorized: Int, categoryName: String?)
}

public struct TransactionSave: Hashable, Sendable {
    public var transaction: Transaction
    public var payeeName: String?
    /// Payees typed into split lines, by line id; lines without an entry keep theirs.
    public var subPayeeNames: [String: String]
    public var isNew: Bool
    public var confirmedReconciledChange: Bool
    public var payeeRename: PayeeRename?

    public init(
        transaction: Transaction, payeeName: String?, subPayeeNames: [String: String] = [:], isNew: Bool,
        confirmedReconciledChange: Bool = false, payeeRename: PayeeRename? = nil
    ) {
        self.transaction = transaction
        self.payeeName = payeeName
        self.subPayeeNames = subPayeeNames
        self.isNew = isNew
        self.confirmedReconciledChange = confirmedReconciledChange
        self.payeeRename = payeeRename
    }
}

public enum ReconciledWarning: Hashable, Sendable {
    case transaction(accountOrAmountChanged: Bool)
    case counterpart(amountChanged: Bool)
    case counterpartPayee

    public static let instruction = "Abgeglichene Buchung trotzdem ändern?"
    public static let confirmTitle = "Ändern"
    public static let cancelTitle = "Abbrechen"

    public var title: String {
        switch self {
        case .transaction: "Abgeglichene Buchung ändern"
        case .counterpart, .counterpartPayee: "Umbuchung mit abgeglichener Gegenbuchung ändern"
        }
    }

    public var content: String {
        switch self {
        case .transaction(let accountOrAmount):
            "Diese Buchung ist abgeglichen. "
                + (accountOrAmount
                    ? "Mit anderem Konto oder Betrag stimmt der abgeglichene Saldo nicht mehr."
                    : "Mit anderem Datum stimmt der abgeglichene Saldo womöglich nicht mehr.")
        case .counterpart(let amount):
            "Die Gegenbuchung dieser Umbuchung ist abgeglichen. "
                + (amount
                    ? "Mit anderem Betrag stimmt ihr abgeglichener Saldo nicht mehr."
                    : "Mit anderem Datum stimmt ihr abgeglichener Saldo womöglich nicht mehr.")
        case .counterpartPayee:
            "Die Gegenbuchung dieser Umbuchung ist abgeglichen. Mit anderem Empfänger stimmt ihr abgeglichener Saldo "
                + "nicht mehr."
        }
    }
}

extension Budget {
    public func reconciledWarning(original: Transaction, edited: Transaction, payeeName: String?) -> ReconciledWarning?
    {
        let accountChanged = original.accountId != edited.accountId
        let amountChanged = original.amount != edited.amount
        let somethingChanged = accountChanged || original.date != edited.date || amountChanged
        if original.cleared == .reconciled {
            return somethingChanged ? .transaction(accountOrAmountChanged: accountChanged || amountChanged) : nil
        }
        guard let counterpart = original.transferTransactionId.flatMap(transaction(withId:)),
            counterpart.cleared == .reconciled
        else { return nil }
        if somethingChanged { return .counterpart(amountChanged: amountChanged) }
        if let payeeName, !Payee.sameName(payeeName, self.payeeName(of: original)) { return .counterpartPayee }
        return nil
    }

    public func payeeRenameCheck(original: Transaction, newPayeeName: String, categoryId: String?) -> PayeeRenameCheck?
    {
        let oldName = payeeName(of: original)
        let newName = newPayeeName.trimmingCharacters(in: .whitespaces)
        guard !oldName.isEmpty, !newName.isEmpty, !Payee.isTransferPayeeName(oldName),
            !Payee.isTransferPayeeName(newName), !Payee.sameName(oldName, newName),
            let payeeId = original.payeeId, let payee = payee(withId: payeeId), isSuggested(payee)
        else { return nil }
        let matches = transactions.filter { $0.uses(payee: payeeId) && $0.id != original.id }
        guard !matches.isEmpty else { return .renameSilently }
        let uncategorized = matches.filter { $0.payeeId == payeeId && $0.categoryId == nil && !$0.isSplit }.count
        let categoryName =
            categoryId == nil || categoryId == EntityID.splitCategory ? nil : categoryDisplayName(categoryId)
        return .ask(
            oldName: oldName, newName: newName, matches: matches.count, uncategorized: uncategorized,
            categoryName: categoryName)
    }

    public func properPayeeName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let target = Payee.transferTargetAccountName(trimmed), let account = account(named: target) {
            return account.transferPayeeName
        }
        return payee(named: trimmed)?.name ?? text
    }

    public func payee(named name: String, includingTransfers: Bool = false) -> Payee? {
        payees.first { (includingTransfers || !$0.isTransferPayee) && Payee.sameName($0.name, name) }
    }

    mutating func saveTransaction(_ save: TransactionSave) throws {
        let previous = save.isNew ? nil : transaction(withId: save.transaction.id)
        if !save.isNew && previous == nil { throw BudgetError.transactionNotFound(save.transaction.id) }
        let named = try applyingSubPayeeNames(save.subPayeeNames, to: save.transaction)
        var (edited, payeeName) = normalizedForSave(named, payeeName: save.payeeName)
        if let previous, keepsPayee(of: previous, typed: payeeName) {
            edited.payeeId = previous.payeeId
            payeeName = nil
        }
        if let previous {
            edited.cleared = previous.cleared
            edited.approved = previous.approved || edited.approved
            if !previous.approved && differs(previous, edited, payeeName: payeeName) { edited.approved = true }
            if save.confirmedReconciledChange { unreconcile(&edited, previous: previous, payeeName: payeeName) }
            if let payeeName, let rename = save.payeeRename {
                applyPayeeRename(rename, original: previous, newName: payeeName, categoryId: edited.categoryId)
            } else if let payeeName,
                payeeRenameCheck(original: previous, newPayeeName: payeeName, categoryId: edited.categoryId)
                    == .renameSilently
            {
                renamePayee(previous.payeeId, to: payeeName)
            }
            try updateTransaction(edited, payeeName: payeeName)
        } else {
            try addTransaction(edited, payeeName: payeeName)
        }
        rememberLastCategory(of: edited.id)
        rememberSubCategories(of: edited.id)
    }

    /// Names are not unique, so looking up a led transaction's unchanged payee by name could find another.
    private func keepsPayee(of previous: Transaction, typed payeeName: String?) -> Bool {
        guard let payeeName, Payee.sameName(payeeName, self.payeeName(of: previous)) else { return false }
        return isLed(previous.id)
    }

    private func differs(_ original: Transaction, _ edited: Transaction, payeeName: String?) -> Bool {
        let newPayee = payeeName ?? self.payeeName(of: edited)
        return original.date != edited.date || !Payee.sameName(self.payeeName(of: original), newPayee)
            || original.categoryId != edited.categoryId || (original.memo ?? "") != (edited.memo ?? "")
            || original.amount != edited.amount
    }

    private mutating func unreconcile(_ edited: inout Transaction, previous: Transaction, payeeName: String?) {
        if previous.cleared == .reconciled {
            let lastReconciled = account(withId: previous.accountId)?.lastReconciledOn
            if previous.accountId != edited.accountId || lastReconciled.map({ edited.date > $0 }) ?? true {
                edited.cleared = .cleared
            }
        }
        guard let counterpartId = previous.transferTransactionId, let index = transactionIndex(counterpartId),
            transactions[index].cleared == .reconciled
        else { return }
        let lastReconciled = account(withId: transactions[index].accountId)?.lastReconciledOn
        let payeeChanged = payeeName.map { !Payee.sameName($0, self.payeeName(of: previous)) } ?? false
        if payeeChanged || lastReconciled.map({ edited.date > $0 }) ?? true {
            transactions[index].cleared = .cleared
        }
    }

    private mutating func applyPayeeRename(
        _ rename: PayeeRename, original: Transaction, newName: String, categoryId: String?
    ) {
        guard let check = payeeRenameCheck(original: original, newPayeeName: newName, categoryId: categoryId),
            let oldId = original.payeeId
        else { return }
        guard case .ask = check else {
            renamePayee(oldId, to: newName)
            return
        }
        let matchIds = transactions.filter { $0.payeeId == oldId && $0.id != original.id }.map(\.id)
        if rename.stopAsking, let index = payees.firstIndex(where: { $0.id == oldId }) {
            payees[index].hidden = true
        }
        guard rename.choice != .leave else { return }
        let renamedId = renamePayee(oldId, to: newName)
        guard rename.choice == .renameAndCategorize, let categoryId, categoryId != EntityID.splitCategory else {
            return
        }
        for index in transactions.indices
        where matchIds.contains(transactions[index].id) && transactions[index].categoryId == nil
            && !transactions[index].isSplit
        {
            transactions[index].categoryId = categoryId
        }
        if let index = payees.firstIndex(where: { $0.id == renamedId }) {
            payees[index].lastCategoryId = categoryId
        }
    }

    private mutating func rememberLastCategory(of transactionId: String) {
        guard let saved = transaction(withId: transactionId), let categoryId = saved.categoryId,
            let index = payees.firstIndex(where: { $0.id == saved.payeeId })
        else { return }
        payees[index].lastCategoryId = categoryId
    }

    private mutating func rememberSubCategories(of transactionId: String) {
        for sub in transaction(withId: transactionId)?.subtransactions ?? [] {
            guard let categoryId = sub.categoryId, let payeeId = sub.payeeId,
                let index = payees.firstIndex(where: { $0.id == payeeId && !$0.isTransferPayee })
            else { continue }
            payees[index].lastCategoryId = categoryId
        }
    }
}
