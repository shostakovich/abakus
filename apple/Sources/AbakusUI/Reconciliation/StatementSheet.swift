import AbakusCore
import SwiftUI

struct StatementSheet: View {
    let model: RegisterViewModel
    @Bindable var form: ReconciliationStatementForm
    @FocusState private var focused: Field?

    enum Field: Hashable { case date, amount }

    private var reconciliation: RegisterReconciliationController { model.reconciliation }

    var body: some View {
        FormSheet(
            title: ReconciliationStatementForm.title, message: intro, confirmTitle: form.beginTitle,
            canConfirm: form.canBegin, onConfirm: { reconciliation.begin(form) },
            onCancel: reconciliation.statementCancelled
        ) {
            Section {
                FormSheetRow(ReconciliationStatementForm.dateQuestion) {
                    HStack(spacing: 8) {
                        TextField(ReconciliationStatementForm.dateQuestion, text: dateText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .focused($focused, equals: .date)
                            .onChange(of: focused) { if focused != .date { reconciliation.commitStatementDate(form) } }
                        CalendarPopoverButton(date: chosenDate, locale: model.formatter.dateLocale)
                    }
                }
                FormSheetRow(ReconciliationStatementForm.balanceQuestion) {
                    TextField(ReconciliationStatementForm.balanceQuestion, text: $form.amountText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: .amount)
                } footnote: {
                    Text(reconciliation.statementHint(form)).formFootnote()
                    Button("Betrag übernehmen") { reconciliation.useClearedBalance(form) }
                        .controlSize(.small)
                }
            }
        }
        .defaultFocus($focused, .amount)
        .onAppear { focused = .amount }
    }

    private var intro: Text {
        Text(ReconciliationStatementForm.intro)
    }

    private var dateText: Binding<String> {
        Binding(
            get: { form.typedDate ?? model.formatter.dateShort(form.date) },
            set: { form.typedDate = $0 })
    }

    private var chosenDate: Binding<DateWithoutTime> {
        Binding(
            get: { form.date },
            set: {
                form.date = $0
                form.typedDate = nil
            })
    }
}
