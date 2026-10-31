import Foundation

public enum ErrorMessages {
    public static let needsCategory =
        "Diese Buchung braucht eine Kategorie. (Buchungen in Budgetkonten brauchen eine Kategorie, damit das "
        + "Budget sie kennt.)"
    public static let offBudgetTransferNeedsCategory =
        "Umbuchungen mit einem Trackingkonto brauchen eine Kategorie. (Geld, das ins Budget kommt oder es "
        + "verlässt, braucht eine Kategorie, damit das Budget es kennt.)"
    public static let onBudgetTransferCategorized =
        "Diese Buchung ist eine Umbuchung zwischen Budgetkonten und braucht keine Kategorie. (Umbuchungen "
        + "zwischen Budgetkonten ändern das Budget nicht.)"
    public static let splitPrefix = "Diese Aufteilung hat folgende Probleme:\n\n"
    public static let enteredByScheduler =
        "Diese geplante Buchung wurde automatisch angelegt. Prüfe sie und bestätige oder lösche sie."
    public static let imported =
        "Diese Buchung wurde importiert. Prüfe sie und bestätige oder lösche sie."
}

extension Budget {
    public func errorState(of transaction: Transaction) -> ErrorState {
        errorState(of: transaction, transfers: transferAccountId(ofPayee:))
    }

    public func errorState(of sub: Subtransaction, inAccount accountId: String) -> ErrorState {
        errorState(of: sub, inAccount: accountId, transfers: transferAccountId(ofPayee:))
    }

    /// `transfers` gives the account a payee transfers to, so a caller with many rows can look it up fast.
    func errorState(of transaction: Transaction, transfers: (String?) -> String?) -> ErrorState {
        var state: ErrorState
        if transaction.isSplit {
            state = splitErrorState(of: transaction, transfers: transfers)
        } else {
            state = categoryErrorState(
                accountId: transaction.accountId, categoryId: transaction.categoryId, amount: transaction.amount,
                transferAccountId: transfers(transaction.payeeId))
        }
        if !transaction.approved && state.level <= .forReview {
            if transaction.source == .scheduled {
                state = ErrorState(level: .forReview, message: ErrorMessages.enteredByScheduler)
            } else if transaction.source != .manual {
                state = ErrorState(level: .forReview, message: ErrorMessages.imported)
            }
        }
        return state
    }

    func errorState(of sub: Subtransaction, inAccount accountId: String, transfers: (String?) -> String?)
        -> ErrorState
    {
        categoryErrorState(
            accountId: accountId, categoryId: sub.categoryId, amount: sub.amount,
            transferAccountId: transfers(sub.payeeId))
    }

    private func splitErrorState(of transaction: Transaction, transfers: (String?) -> String?) -> ErrorState {
        let childStates = transaction.subtransactions.map {
            errorState(of: $0, inAccount: transaction.accountId, transfers: transfers)
        }
        .filter { $0.level != .none }
        guard let worst = childStates.map(\.level).max() else { return .noError }
        let details = childStates.map { "\t- \($0.message)\n\n" }.joined()
        return ErrorState(level: worst, message: ErrorMessages.splitPrefix + details)
    }

    private func categoryErrorState(
        accountId: String, categoryId: String?, amount: Decimal, transferAccountId: String?
    ) -> ErrorState {
        guard let owner = account(withId: accountId), owner.onBudget else { return .noError }
        let target = transferAccountId.flatMap { account(withId: $0) }
        let isCategorized = EntityID.isCategorized(categoryId)
        if !isCategorized {
            guard amount != 0 else { return .noError }
            guard let target else { return ErrorState(level: .needsCategory, message: ErrorMessages.needsCategory) }
            return target.onBudget
                ? .noError : ErrorState(level: .needsCategory, message: ErrorMessages.offBudgetTransferNeedsCategory)
        }
        if let target, target.onBudget {
            return ErrorState(level: .error, message: ErrorMessages.onBudgetTransferCategorized)
        }
        return .noError
    }
}
