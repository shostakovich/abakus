#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct AddAccountSheet: View {
        let controller: AccountsController
        @Bindable var form: AddAccountForm
        @FocusState private var isNameFocused: Bool

        var body: some View {
            let calendar = controller.formatter.dateLocale.calendar
            NavigationStack {
                Form {
                    Section("Name") {
                        TextField("Name", text: $form.name).focused($isNameFocused)
                    }
                    Section {
                        LabeledContent("Aktueller Saldo") {
                            AmountTextField(title: "Aktueller Saldo", text: $form.balanceText)
                        }
                        DatePicker(
                            "Datum des Saldos",
                            selection: Binding(
                                get: { form.date.date(in: calendar) },
                                set: { form.date = DateWithoutTime($0, in: calendar) }),
                            displayedComponents: .date)
                    } footer: {
                        Text("Lässt sich später jederzeit ändern.")
                    }
                    Section {
                        Picker("Art", selection: $form.type) {
                            Text(AddAccountForm.typePlaceholder).tag(AccountKind?.none)
                            ForEach(AccountKind.budgetKinds, id: \.self) { type in
                                Text(verbatim: type.label).tag(AccountKind?.some(type))
                            }
                            Divider()
                            Text(verbatim: AccountKind.tracking.label).tag(AccountKind?.some(.tracking))
                        }
                    } footer: {
                        Text(AddAccountForm.typeHint)
                    }
                }
                .navigationTitle("Neues Konto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark", role: .close, action: controller.addCancelled)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(
                            "Hinzufügen", systemImage: "checkmark", role: .confirm,
                            action: controller.createAccountClicked
                        )
                        .disabled(!form.canCreate)
                    }
                }
                .defaultFocus($isNameFocused, true)
            }
        }
    }

    struct EditAccountSheet: View {
        let controller: AccountsController
        @Bindable var form: EditAccountForm

        var body: some View {
            let isClosed = controller.isClosed(form)
            NavigationStack {
                Form {
                    Section("Name") {
                        TextField("Name", text: $form.name).onSubmit(controller.editDoneClicked)
                    }
                    Section {
                        if form.typeChoices.count > 1 {
                            Picker("Art", selection: $form.type) {
                                ForEach(form.typeChoices, id: \.self) { type in
                                    Text(verbatim: type.label).tag(type)
                                }
                            }
                        } else {
                            LabeledContent("Art") { Text(verbatim: form.type.label) }
                        }
                        Button("Saldo anpassen …", action: controller.adjustBalanceClicked)
                    }
                    Section {
                        Button(
                            isClosed ? "Wieder öffnen" : "Konto schließen", role: isClosed ? nil : .destructive,
                            action: controller.closeOrReopenClicked)
                    }
                }
                .navigationTitle(EditAccountForm.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark", role: .close, action: controller.editCancelled)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig", systemImage: "checkmark", role: .confirm, action: controller.editDoneClicked)
                    }
                }
            }
        }
    }

    struct AdjustBalanceSheet: View {
        let controller: AccountsController
        @Bindable var form: AdjustBalanceForm
        @FocusState private var isAmountFocused: Bool

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        LabeledContent(form.fieldLabel) {
                            AmountTextField(title: form.fieldLabel, text: $form.amountText)
                                .focused($isAmountFocused)
                                .onSubmit(controller.adjustClicked)
                        }
                    } footer: {
                        Text("\(form.instruction)\n\(AdjustBalanceForm.hint)\(Text(form.workingBalanceText).bold())")
                    }
                }
                .navigationTitle("Saldo anpassen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark", role: .close, action: controller.balanceCancelled)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(
                            AdjustBalanceForm.buttonTitle, systemImage: "checkmark", role: .confirm,
                            action: controller.adjustClicked)
                    }
                }
                .defaultFocus($isAmountFocused, true)
            }
        }
    }

    /// A balance may be negative, so the keypad keeps the minus.
    private struct AmountTextField: View {
        let title: String
        @Binding var text: String

        var body: some View {
            TextField(title, text: $text)
                .amountKeyboard()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
#endif
