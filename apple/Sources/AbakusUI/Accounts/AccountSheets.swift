import AbakusCore
import SwiftUI

struct AddAccountSheet: View {
    let controller: AccountsController
    @Bindable var form: AddAccountForm
    @FocusState private var nameFocused: Bool

    var body: some View {
        let formatter = controller.formatter
        FormSheet(
            title: AddAccountForm.title, confirmTitle: "Hinzufügen", canConfirm: form.canCreate,
            onConfirm: controller.createAccountClicked, onCancel: controller.addCancelled
        ) {
            Section {
                FormSheetRow("Name") {
                    TextField("Name", text: $form.name)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($nameFocused)
                }
            }
            Section {
                FormSheetRow("Aktueller Saldo") {
                    TextField("Aktueller Saldo", text: $form.balanceText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                } footnote: {
                    Text("Lässt sich später jederzeit ändern.").formFootnote()
                }
                FormSheetRow("Datum des Saldos") {
                    HStack(spacing: 8) {
                        DatePicker(
                            "Datum des Saldos",
                            selection: Binding(
                                get: { form.date.date(in: formatter.dateLocale.calendar) },
                                set: { form.date = DateWithoutTime($0, in: formatter.dateLocale.calendar) }),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .environment(\.locale, Locale(identifier: formatter.dateLocale.identifier))
                        CalendarPopoverButton(date: $form.date, locale: formatter.dateLocale)
                    }
                }
            }
            Section {
                FormSheetRow("Art") {
                    Picker("Art", selection: $form.type) {
                        Text(AddAccountForm.typePlaceholder).tag(AccountKind?.none)
                        ForEach(AccountKind.budgetKinds, id: \.self) { type in
                            Text(type.label).tag(AccountKind?.some(type))
                        }
                        Divider()
                        Text(AccountKind.tracking.label).tag(AccountKind?.some(.tracking))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } footnote: {
                    Text(AddAccountForm.typeHint).formFootnote()
                }
            }
        }
        .defaultFocus($nameFocused, true)
    }
}

struct AdjustBalanceSheet: View {
    let controller: AccountsController
    @Bindable var form: AdjustBalanceForm
    @FocusState private var amountFocused: Bool

    var body: some View {
        FormSheet(
            title: form.title, message: Text(form.instruction), confirmTitle: AdjustBalanceForm.buttonTitle,
            onConfirm: controller.adjustClicked, onCancel: controller.balanceCancelled
        ) {
            FormSheetRow(form.fieldLabel) {
                TextField(form.fieldLabel, text: $form.amountText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($amountFocused)
            } footnote: {
                Text("\(AdjustBalanceForm.hint)\(Text(form.workingBalanceText).bold())").formFootnote()
            }
        }
        .defaultFocus($amountFocused, true)
    }
}
