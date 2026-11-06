import AbakusCore
import AbakusUI
import SwiftUI

struct AddAccountSheet: View {
    let controller: AccountsController
    @Bindable var form: AddAccountForm
    @FocusState private var nameFocused: Bool

    var body: some View {
        FormSheet(
            title: AddAccountForm.title, note: AddAccountForm.typeHint, confirmTitle: "Hinzufügen",
            canConfirm: form.canCreate, onConfirm: controller.createAccountClicked, onCancel: controller.addCancelled
        ) {
            Section {
                FormSheetRow("Name") {
                    TextField("Name", text: $form.name, prompt: Text("z. B. Girokonto"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($nameFocused)
                }
                FormSheetRow("Art") {
                    Picker("Art", selection: $form.type) {
                        ForEach(AccountKind.budgetKinds, id: \.self) { type in
                            Text(verbatim: type.label).tag(type)
                        }
                        Divider()
                        Text(verbatim: AccountKind.tracking.label).tag(AccountKind.tracking)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                FormSheetRow("Aktueller Saldo") {
                    TextField("Aktueller Saldo", text: $form.balanceText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
        }
        .defaultFocus($nameFocused, true)
    }
}

struct ClosedAccountsSheet: View {
    let register: RegisterViewModel
    @State private var selection: String?

    var body: some View {
        let rows = register.closedAccounts
        VStack(alignment: .leading, spacing: 12) {
            Text(RegisterViewModel.closedAccountsTitle).font(.headline)
            List(rows, selection: $selection) { row in
                HStack(spacing: 12) {
                    Text(verbatim: row.name).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(verbatim: row.detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(row.id)
            }
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first { register.closedAccountChosen(id) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: min(CGFloat(max(rows.count, 3)) * 28 + 8, 280))
            Text("Doppelklick öffnet das Konto.").formFootnote()
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button("Fertig", action: register.closedAccountsDismissed).keyboardShortcut(.cancelAction)
                Button("Öffnen") {
                    if let selection { register.closedAccountChosen(selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { selection = rows.first?.id }
    }
}
