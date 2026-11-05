#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct StatementSheet: View {
        let register: RegisterViewModel
        @Bindable var form: ReconciliationStatementForm
        let dialogs: [PresentedDialog]
        @FocusState private var isAmountFocused: Bool

        private var reconciliation: RegisterReconciliationController { register.reconciliation }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Text(ReconciliationStatementForm.intro)
                            .font(.subheadline)
                            .foregroundStyle(ThemeColor.secondaryText)
                            .listRowBackground(Color.clear)
                    }
                    Section(ReconciliationStatementForm.dateQuestion) {
                        DatePicker("Datum", selection: date, displayedComponents: .date)
                    }
                    Section {
                        TextField("Banksaldo", text: $form.amountText)
                            .amountKeyboard()
                            .monospacedDigit()
                            .focused($isAmountFocused)
                            .submitLabel(.done)
                            .onSubmit { reconciliation.begin(form) }
                    } header: {
                        Text(ReconciliationStatementForm.balanceQuestion)
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reconciliation.statementHint(form))
                            Button("Betrag übernehmen") { reconciliation.useClearedBalance(form) }
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
                .navigationTitle(ReconciliationStatementForm.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(
                            "Abbrechen", systemImage: "xmark", role: .close, action: reconciliation.statementCancelled)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(form.beginTitle, systemImage: "checkmark", role: .confirm) { reconciliation.begin(form) }
                            .disabled(!form.canBegin)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(ThemeColor.groupedBackground)
            .presentationDragIndicator(.visible)
            .onAppear { isAmountFocused = true }
            .modifier(DialogAlert(dialogs: dialogs))
        }

        private var date: Binding<Date> {
            let calendar = register.formatter.dateLocale.calendar
            return Binding {
                form.date.date(in: calendar)
            } set: {
                form.date = DateWithoutTime($0, in: calendar)
                form.typedDate = nil
            }
        }
    }

    struct ReconciliationBar: View {
        let reconciliation: RegisterReconciliationController
        let footer: ReconciliationFooterModel
        @State private var showsDetails = false
        @State private var chosen: ReconciliationAction?

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    reconciliation.perform(.adjust)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Banksaldo").foregroundStyle(ThemeColor.secondaryText)
                        Text(verbatim: footer.statementBalance)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(ThemeColor.text)
                        Text(verbatim: "am \(footer.statementDate)").foregroundStyle(ThemeColor.secondaryText)
                        Spacer(minLength: 4)
                        Image(systemName: "pencil")
                            .foregroundStyle(ThemeColor.accent)
                            .accessibilityHidden(true)
                    }
                    .minimumScaleFactor(0.8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(ReconciliationFooterModel.adjustTitle)
                HStack(spacing: 12) {
                    Button {
                        showsDetails = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: ReconciliationFooterModel.differenceTitle)
                                .foregroundStyle(ThemeColor.secondaryText)
                            ReconciliationDifferenceText(footer: footer).fontWeight(.semibold)
                            Image(systemName: "chevron.up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ThemeColor.secondaryText)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Zeigt den Abgleich im Einzelnen")
                    Spacer(minLength: 8)
                    ProminentButton(title: ReconciliationAction.finish.title) { reconciliation.perform(.finish) }
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            // The chosen action runs once the sheet is gone, so its dialog or form can show.
            .sheet(isPresented: $showsDetails, onDismiss: performChosen) {
                ReconciliationSheet(reconciliation: reconciliation) { action in
                    chosen = action
                    showsDetails = false
                }
            }
        }

        private func performChosen() {
            guard let action = chosen else { return }
            chosen = nil
            reconciliation.perform(action)
        }
    }

    private struct ReconciliationSheet: View {
        let reconciliation: RegisterReconciliationController
        let choose: (ReconciliationAction) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    if let footer = reconciliation.footer {
                        Section {
                            ForEach(Array(footer.rows.enumerated()), id: \.offset) { _, row in
                                LabeledContent {
                                    ReconciliationOperandText(row: row)
                                } label: {
                                    Text(verbatim: row.label)
                                }
                            }
                            LabeledContent(ReconciliationFooterModel.differenceTitle) {
                                ReconciliationDifferenceText(footer: footer).fontWeight(.semibold)
                            }
                        } footer: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: footer.message)
                                Text("Die Liste zeigt die Buchungen bis zum Datum des Banksaldos.")
                            }
                        }
                    }
                    Section {
                        Button(ReconciliationAction.finish.title) { choose(.finish) }
                        Button(ReconciliationAction.adjust.title) { choose(.adjust) }
                        Button(ReconciliationAction.stop.title, role: .destructive) { choose(.stop) }
                    }
                }
                .navigationTitle(ReconciliationStatementForm.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen", systemImage: "xmark", role: .close) { dismiss() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(ThemeColor.groupedBackground)
            .presentationDragIndicator(.visible)
        }
    }

    /// One text, so a value that wraps under its label starts at the edge, and "=" keeps a single space like "+".
    private struct ReconciliationOperandText: View {
        let row: ReconciliationFooterRow

        var body: some View {
            let value = Text(verbatim: row.value).foregroundStyle(ThemeColor.text)
            Group {
                if let operation = row.operation {
                    Text("\(Text(verbatim: operation.rawValue).foregroundStyle(ThemeColor.secondaryText)) \(value)")
                } else {
                    value
                }
            }
            .monospacedDigit()
            .accessibilityLabel(row.value)
        }
    }

    private struct ReconciliationDifferenceText: View {
        let footer: ReconciliationFooterModel

        var body: some View {
            Text(verbatim: footer.difference)
                .monospacedDigit()
                .foregroundStyle(footer.isBalanced ? ThemeColor.positive : ThemeColor.negative)
        }
    }
#endif
