#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct AddAccountSheet: View {
        let controller: AccountsController
        @Bindable var form: AddAccountForm
        @FocusState private var isNameFocused: Bool

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $form.name).focused($isNameFocused)
                        Picker("Art", selection: $form.type) {
                            ForEach(AccountKind.budgetKinds, id: \.self) { type in
                                Text(verbatim: type.label).tag(type)
                            }
                            Divider()
                            Text(verbatim: AccountKind.tracking.label).tag(AccountKind.tracking)
                        }
                        LabeledContent("Aktueller Saldo") {
                            AmountTextField(title: "Aktueller Saldo", text: $form.balanceText)
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
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $form.name).onSubmit(controller.editDoneClicked)
                        if form.typeChoices.count > 1 {
                            Picker("Art", selection: $form.type) {
                                ForEach(form.typeChoices, id: \.self) { type in
                                    Text(verbatim: type.label).tag(type)
                                }
                            }
                        } else {
                            LabeledContent("Art") { Text(verbatim: form.type.label) }
                        }
                    }
                    if form.canClose {
                        Section {
                            Button(
                                EditAccountForm.closeTitle.touchLabel, role: .destructive,
                                action: controller.closeAccountClicked)
                        }
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

    struct ClosedAccountsSheet: View {
        let register: RegisterViewModel

        var body: some View {
            NavigationStack {
                List(register.closedAccounts) { row in
                    Button {
                        register.closedAccountChosen(row.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: row.name).foregroundStyle(ThemeColor.text).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(verbatim: row.detail)
                                .monospacedDigit()
                                .foregroundStyle(ThemeColor.secondaryText)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(RegisterViewModel.closedAccountsTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(
                            "Schließen", systemImage: "xmark", role: .close, action: register.closedAccountsDismissed)
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
