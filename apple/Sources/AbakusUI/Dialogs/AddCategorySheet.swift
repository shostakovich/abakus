import SwiftUI

struct AddCategorySheet: View {
    enum Field: Hashable { case master, name }

    let request: AddCategoryRequest
    @State private var master: String
    @State private var name: String
    @State private var lastFocused: Field?
    @FocusState private var focused: Field?

    init(request: AddCategoryRequest) {
        self.request = request
        _master = State(initialValue: request.form.masterName)
        _name = State(initialValue: request.form.name)
    }

    private var form: AddCategoryForm { request.form }

    var body: some View {
        FormSheet(
            title: "Neue Kategorie", confirmTitle: "Anlegen", onConfirm: { request.onCreate(master, name) },
            onCancel: request.onCancel
        ) {
            Section("1. Gruppe der neuen Kategorie wählen") {
                FormSheetRow("Gruppe") {
                    TextField("Gruppe", text: $master)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($focused, equals: .master)
                        .textInputSuggestions {
                            ForEach(suggestions, id: \.self) { Text($0).textInputCompletion($0) }
                        }
                } footnote: {
                    Text("Wähle eine bestehende Gruppe oder gib den Namen einer neuen ein.").formFootnote()
                }
            }
            Section("2. Namen der neuen Kategorie eingeben") {
                FormSheetRow("Name") {
                    TextField("Name", text: $name)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($focused, equals: .name)
                }
            }
        }
        .defaultFocus($focused, form.masterName.isEmpty ? .master : .name)
        .onChange(of: focused) { if let focused { lastFocused = focused } }
        .onChange(of: form.refocusRequest) { focused = lastFocused ?? (master.isEmpty ? .master : .name) }
    }

    private var suggestions: [String] {
        request.masterNames.filter { master.isEmpty || $0.localizedCaseInsensitiveContains(master) }
    }
}
