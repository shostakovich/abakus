import AbakusCore
import Foundation

/// The register's move warning and the editor's save warning are the same dialog.
enum ReconciledChoice: Hashable, Sendable {
    case change, keep
}

enum PayeeRenameChoice: Hashable, Sendable {
    case renameAndCategorize, rename, leave, cancel
}

enum UnassignedChoice: Hashable, Sendable {
    case manuallyAdjust, autoDistribute, adjustTotal, cancel
}

extension TaskDialog where Choice == ReconciledChoice {
    static func reconciledChange(title: String, content: String) -> Self {
        TaskDialog(
            title: title, instruction: ReconciledWarning.instruction, content: content,
            buttons: [
                .init(.change, title: ReconciledWarning.confirmTitle),
                .init(.keep, title: ReconciledWarning.cancelTitle, isDefault: true),
            ],
            dismissal: .keep)
    }
}

extension TransactionEditor {
    public func activate(_ button: EditorButton) {
        guard !hasOpenDialog else { return }
        switch button {
        case .done, .save: commitChange(addAnother: false, findNext: false)
        case .saveAndAddAnother: commitChange(addAnother: true, findNext: false)
        case .approve:
            clone.approved = true
            commitChange(addAnother: false, findNext: false)
        case .approveAndFindNext:
            clone.approved = true
            commitChange(addAnother: false, findNext: true)
        case .delete:
            closePopups()
            onFinish(.deleteRequested(transactionId: transactionId))
        case .cancel:
            cancel()
        }
    }

    public func commitForQuit() {
        guard !hasOwnDialog else { return }
        commitChange(addAnother: false, findNext: false)
    }

    func commitChange(addAnother: Bool, findNext: Bool) {
        if let field = focus?.field {
            closePopups()
            blur(field)
            showsButtonFocus = false
            focus = .button(defaultButton)
        }
        refocusRequest = nil
        if blockNextSave {
            blockNextSave = false
            setFocus(.field(.main(.date)), commitCurrent: false)
            return
        }
        guard !hasOwnDialog else { return }
        if mode == .new && isEmptyNewTransaction {
            cancel()
            return
        }
        pendingSave = PendingSave(addAnother: addAnother, findNext: findNext)
        continueSave()
    }

    var isEmptyNewTransaction: Bool {
        payeeName.trimmingCharacters(in: .whitespaces).isEmpty && clone.categoryId == nil
            && (clone.memo ?? "").isEmpty && clone.amount == 0
    }

    func continueSave() {
        guard var pending = pendingSave else { return }
        if mode == .existing && !isScheduled {
            if pending.reconciledConfirmed == nil {
                if let warning = budget.reconciledWarning(original: original, edited: clone, payeeName: payeeName) {
                    ask(.reconciledChange(title: warning.title, content: warning.content)) { [weak self] answer in
                        self?.reconciledAnswered(answer.choice)
                    }
                    return
                }
                pending.reconciledConfirmed = false
            }
            if pending.payeeRename == nil,
                case .ask(let oldName, let newName, let matches, let uncategorized, let categoryName) =
                    budget.payeeRenameCheck(original: original, newPayeeName: payeeName, categoryId: clone.categoryId)
            {
                pendingSave = pending
                ask(
                    Self.payeeRenameDialog(
                        oldName: oldName, newName: newName, matches: matches, uncategorized: uncategorized,
                        categoryName: categoryName)
                ) { [weak self] answer in
                    self?.payeeRenameAnswered(answer)
                }
                return
            }
        }
        pendingSave = pending
        let normalized = SplitRules.normalized(
            rebasedOnStored(preparedTransaction()), parentPayeeName: payeeName, subPayeeNames: subPayeeNames,
            in: budget)
        if normalized.isSplit && SplitRules.unassigned(normalized) != 0 {
            ask(unassignedDialog(normalized)) { [weak self] answer in
                self?.unassignedAnswered(answer.choice, normalized)
            }
            return
        }
        perform(normalized)
    }

    /// The clone as it is copied: lines only while the category is the split.
    func preparedTransaction() -> Transaction {
        var transaction = clone
        if transaction.categoryId == EntityID.splitCategory {
            for index in transaction.subtransactions.indices {
                transaction.subtransactions[index].transactionId = transaction.id
            }
        } else {
            transaction.subtransactions = []
        }
        return transaction
    }

    /// Another writer's change that arrived while the editor was open stays.
    private func rebasedOnStored(_ edited: Transaction) -> Transaction {
        guard mode == .existing, !isScheduled, let current = budget.transaction(withId: edited.id) else {
            return edited
        }
        return edited.rebased(from: original, onto: current, partsChanged: !subPayeeNames.isEmpty)
    }

    private var savedPayeeName: String? {
        guard mode == .existing, !isScheduled, Payee.sameName(payeeName, originalPayeeName) else { return payeeName }
        return nil
    }

    private func perform(_ transaction: Transaction) {
        guard let pending = pendingSave else { return }
        let save = TransactionSave(
            transaction: transaction, payeeName: savedPayeeName, subPayeeNames: subPayeeNames, isNew: mode == .new,
            confirmedReconciledChange: pending.reconciledConfirmed ?? false, payeeRename: pending.payeeRename)
        do {
            if let frequency {
                try store.perform(
                    .saveScheduledTransaction(
                        ScheduledSave(
                            transaction: transaction, frequency: frequency, payeeName: payeeName,
                            subPayeeNames: subPayeeNames, isNew: mode == .new)))
            } else {
                try store.perform(.saveTransaction(save))
            }
        } catch let error as BudgetError where error.dialogContent != nil {
            pendingSave = nil
            showRefusal(error, refocus: error == .transferToSameAccount ? .main(.payee) : nil)
            return
        } catch {
            pendingSave = nil
            showMessage(.message(error.localizedDescription, ""), refocus: nil)
            return
        }
        pendingSave = nil
        let saved = store.budget.transaction(withId: transaction.id)
        let incomeCheck = leader == nil && (saved?.outflow ?? 0) > 0 && budget.isReadyToAssign(saved?.categoryId)
        onFinish(
            .saved(
                transactionId: transaction.id, addAnother: pending.addAnother, findNext: pending.findNext,
                incomeCheck: incomeCheck))
    }

    private func ask<Choice>(
        _ dialog: TaskDialog<Choice>, then continuation: @escaping @MainActor (TaskDialogAnswer<Choice>) -> Void
    ) {
        dropDown = nil
        dialogs.ask(dialog, owner: self, then: continuation)
    }

    private func reconciledAnswered(_ choice: ReconciledChoice) {
        guard choice == .change else {
            cancel()
            return
        }
        pendingSave?.reconciledConfirmed = true
        continueSave()
    }

    private func payeeRenameAnswered(_ answer: TaskDialogAnswer<PayeeRenameChoice>) {
        let choice: PayeeRename.Choice
        switch answer.choice {
        case .rename: choice = .rename
        case .renameAndCategorize: choice = .renameAndCategorize
        case .leave: choice = .leave
        case .cancel:
            pendingSave = nil
            return
        }
        pendingSave?.payeeRename = PayeeRename(choice: choice, stopAsking: answer.isChecked)
        continueSave()
    }

    private func unassignedAnswered(_ choice: UnassignedChoice, _ normalized: Transaction) {
        switch choice {
        case .autoDistribute: perform(SplitRules.autoDistribute(normalized))
        case .adjustTotal:
            let adjusted = SplitRules.adjustOriginal(normalized)
            clone.amount = adjusted.amount
            refreshAmountText(subId: nil)
            perform(adjusted)
        case .manuallyAdjust, .cancel:
            pendingSave = nil
        }
    }

    static func payeeRenameDialog(
        oldName: String, newName: String, matches: Int, uncategorized: Int, categoryName: String?
    ) -> TaskDialog<PayeeRenameChoice> {
        let rename = "\(matches) passende Buchungen in „\(newName)“ umbenennen"
        var links: [TaskDialog<PayeeRenameChoice>.CommandLink]
        if let categoryName, uncategorized > 0 {
            links = [
                .init(
                    .renameAndCategorize, title: "Umbenennen und kategorisieren",
                    detail: rename
                        + ". \(uncategorized) Buchungen ohne Kategorie als „\(categoryName)“ kategorisieren.",
                    isDefault: true),
                .init(
                    .rename, title: "Nur umbenennen",
                    detail: rename + ". Buchungen ohne Kategorie nicht kategorisieren."),
            ]
        } else {
            links = [
                .init(
                    .rename, title: "Umbenennen", detail: categoryName == nil ? rename : rename + ".", isDefault: true)
            ]
        }
        links.append(
            .init(
                .leave, title: "Unverändert lassen",
                detail: "Nur diese Buchung ändern, die anderen nicht."))
        return TaskDialog(
            instruction: "Passende Buchungen auch ändern?",
            content: "\(matches) weitere Buchungen haben diesen Empfänger:<br/>&nbsp;&nbsp;„<b>\(oldName)</b>“"
                + "<br/>Was soll mit ihnen geschehen?<br/>",
            commandLinks: links, buttons: [.init(.cancel, title: "Abbrechen")],
            checkbox: "Bei diesem Empfänger nicht mehr fragen", dismissal: .cancel)
    }

    func unassignedDialog(_ transaction: Transaction) -> TaskDialog<UnassignedChoice> {
        let formatter = formatter
        let unassigned = formatter.currency(SplitRules.unassigned(transaction))
        let total = formatter.currency(transaction.amount)
        let sum = formatter.currency(Amount.sum(transaction.subtransactions.map(\.amount)))
        return TaskDialog(
            instruction: "Was soll mit den noch nicht aufgeteilten <b>\(unassigned)</b> geschehen?",
            content: "Die Buchung beträgt <b>\(total)</b>, die Teile ergeben aber <b>\(sum)</b>. "
                + "<b>\(unassigned)</b> sind noch aufzuteilen.",
            commandLinks: [
                .init(.manuallyAdjust, title: "Teile selbst anpassen", detail: "Die Buchung weiter bearbeiten."),
                .init(
                    .autoDistribute, title: "Auf die Teile verteilen",
                    detail: "\(unassigned) anteilig auf die eingegebenen Teile verteilen (etwa für Steuern)."),
                .init(
                    .adjustTotal, title: "Buchung anpassen",
                    detail: "Den Betrag der Buchung auf \(sum) setzen."),
            ],
            buttons: [.init(.cancel, title: "Abbrechen")], dismissal: .cancel)
    }
}
