import SwiftUI

struct RenamePayeeSheet: View {
    let form: RenamePayeeForm
    let onRename: (String) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(form: RenamePayeeForm, onRename: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.form = form
        self.onRename = onRename
        self.onCancel = onCancel
        _name = State(initialValue: form.currentName)
    }

    var body: some View {
        FormSheet(
            title: "Empfänger umbenennen", confirmTitle: "Umbenennen", onConfirm: { onRename(name) }, onCancel: onCancel
        ) {
            FormSheetRow("Bisheriger Name") {
                Text(form.currentName)
            }
            FormSheetRow("Neuer Name") {
                TextField("Neuer Name", text: $name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .focused($isFocused)
            } footnote: {
                Text(form.description).formFootnote()
            }
        }
        .defaultFocus($isFocused, true)
    }
}
