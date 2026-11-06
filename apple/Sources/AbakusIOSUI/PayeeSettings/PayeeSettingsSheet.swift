#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct PayeeSettingsSheet: View {
        let model: PayeeSettingsModel
        let dialogs: [PresentedDialog]
        @State private var path: [PayeeRoute]
        @State private var isPicking = false

        init(model: PayeeSettingsModel, dialogs: [PresentedDialog]) {
            self.model = model
            self.dialogs = dialogs
            _path = State(initialValue: model.state == .single ? [.payee] : [])
        }

        var body: some View {
            NavigationStack(path: $path) {
                PayeeList(model: model, path: $path, isPicking: $isPicking, onClose: model.close)
                    .navigationDestination(for: PayeeRoute.self) { route in
                        PayeePage(model: model, route: route, path: $path, isPicking: $isPicking)
                    }
            }
            .modifier(DialogAlert(dialogs: dialogs))
        }
    }

    struct PayeePage: View {
        let model: PayeeSettingsModel
        let route: PayeeRoute
        @Binding var path: [PayeeRoute]
        @Binding var isPicking: Bool

        var body: some View {
            switch route {
            case .payees: PayeeList(model: model, path: $path, isPicking: $isPicking, onClose: nil)
            case .payee: PayeeForm(model: model)
            case .category: PayeeCategoryList(model: model)
            }
        }
    }

    private struct PayeeList: View {
        static let autoFillFooter =
            "Wählst du in einer neuen Buchung einen Empfänger, ergänzt Abakus die Kategorie, die bei ihm hinterlegt "
            + "ist, und das Memo und den Betrag, die zuletzt mit ihm verwendet wurden. Das gilt für alle Empfänger."

        @Bindable var model: PayeeSettingsModel
        @Binding var path: [PayeeRoute]
        @Binding var isPicking: Bool
        let onClose: (() -> Void)?
        @State private var isCombining = false
        @State private var search = ""
        @State private var filter = PayeeListFilter.listed

        var body: some View {
            let sections = model.sections(showing: filter, matching: search)
            List(selection: picked) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row($0) }
                    } header: {
                        Text(verbatim: section.id)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.secondaryText)
                            .listRowInsets(.vertical, 2)
                    }
                    .sectionIndexLabel(section.id)
                }
                if search.isEmpty && !isPicking {
                    Section {
                        AutoFillToggles(model: model)
                    } header: {
                        Text("Optionen")
                    } footer: {
                        Text(Self.autoFillFooter)
                            .font(.footnote)
                            .foregroundStyle(ThemeColor.secondaryText)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .listSectionIndexVisibility(.visible)
            .readableListWidth()
            .scrollsUnderDock()
            .overlay {
                if sections.isEmpty { emptyState }
            }
            .environment(\.editMode, .constant(isPicking ? .active : .inactive))
            .searchable(
                text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Empfänger suchen"
            )
            .navigationTitle("Empfänger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Ausgewählte Empfänger zusammenfassen und umbenennen?", isPresented: $isCombining) {
                TextField("Neuer Name", text: $model.combineName)
                Button("Abbrechen", role: .cancel) {}
                Button("Zusammenfassen", action: combine).disabled(!model.canCombine)
            } message: {
                Text(PayeeSettingsModel.combineTooltip)
            }
            .onChange(of: path) {
                if !path.contains(.payee) && !isPicking && model.state != .noSelection {
                    model.selectionChanged(to: [])
                }
            }
        }

        @ViewBuilder
        private func row(_ row: PayeeSettingsModel.Row) -> some View {
            if isPicking {
                PayeeRowLabel(row: row, marksHidden: filter == .all).tag(row.id)
            } else {
                Button {
                    model.selectionChanged(to: [row.id])
                    path.append(.payee)
                } label: {
                    PayeeRowLabel(row: row, marksHidden: filter == .all)
                }
                .foregroundStyle(ThemeColor.text)
            }
        }

        @ViewBuilder
        private var emptyState: some View {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if filter == .hidden {
                ContentUnavailableView("Keine ausgeblendeten Empfänger", systemImage: "eye.slash")
            } else {
                ContentUnavailableView("Keine Empfänger", systemImage: "person.2")
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", systemImage: "xmark", role: .close, action: onClose)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Zeigen", selection: $filter) {
                        ForEach(PayeeListFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(
                        "Filter",
                        systemImage: filter == .listed
                            ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityValue(filter.title)
                // Symbols, so the group leaves the title room to stay centred.
                if isPicking {
                    Button("Fertig", systemImage: "checkmark", role: .confirm, action: togglePicking)
                } else {
                    Button("Auswählen", systemImage: "checkmark.circle", action: togglePicking)
                }
            }
            if isPicking {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Zusammenfassen") { isCombining = true }
                        .disabled(model.selection.count < 2)
                    Spacer()
                    Text("\(model.selection.count) ausgewählt").font(.footnote).monospacedDigit()
                    Spacer()
                    Menu("Aufführen", systemImage: "eye") {
                        Button("Aufführen und ergänzen", systemImage: "eye") { model.setSelectedPayeesEnabled(true) }
                        Button("Ausblenden", systemImage: "eye.slash") { model.setSelectedPayeesEnabled(false) }
                    }
                    .disabled(model.selection.isEmpty)
                }
            }
        }

        private var picked: Binding<Set<String>> {
            Binding {
                isPicking ? Set(model.selection) : []
            } set: { ids in
                if isPicking { model.selectionChanged(to: ids) }
            }
        }

        private func togglePicking() {
            model.selectionChanged(to: [])
            isPicking.toggle()
        }

        private func combine() {
            model.combineClicked()
            guard model.state == .single else { return }
            isPicking = false
            path.append(.payee)
        }
    }

    private struct AutoFillToggles: View {
        let model: PayeeSettingsModel

        var body: some View {
            Toggle("Kategorie ergänzen", isOn: setting(\.category))
            Toggle("Memo ergänzen", isOn: setting(\.memo))
            Toggle("Betrag ergänzen", isOn: setting(\.amount))
        }

        private func setting(_ keyPath: WritableKeyPath<AutoFillSettings, Bool>) -> Binding<Bool> {
            Binding(
                get: { model.autoFill[keyPath: keyPath] },
                set: { isOn in
                    var settings = model.autoFill
                    settings[keyPath: keyPath] = isOn
                    model.setAutoFill(settings)
                })
        }
    }

    private struct PayeeRowLabel: View {
        let row: PayeeSettingsModel.Row
        let marksHidden: Bool

        var body: some View {
            HStack(spacing: 6) {
                Text(verbatim: row.name)
                    .fontWeight(row.hasRules ? .semibold : .regular)
                    .foregroundStyle(marksHidden && !row.isEnabled ? ThemeColor.secondaryText : ThemeColor.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if marksHidden && !row.isEnabled {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(ThemeColor.secondaryText)
                        .accessibilityLabel("Ausgeblendet")
                }
            }
            .contentShape(Rectangle())
        }
    }

    private struct PayeeForm: View {
        @Bindable var model: PayeeSettingsModel
        @FocusState private var focus: PayeeSettingsModel.Field?

        var body: some View {
            Form {
                Section {
                    LabeledContent("Name") { Text(verbatim: model.selectedPayeeName) }
                    if !model.isTransfer {
                        Button("Umbenennen", action: model.startRenaming)
                    }
                    Toggle(
                        "Empfänger aufführen und ergänzen",
                        isOn: Binding(
                            get: { model.isSelectedPayeeEnabled }, set: { model.setSelectedPayeeEnabled($0) })
                    )
                    .disabled(model.isTransfer)
                    Button("\(model.transactionCountText) zeigen", action: model.showTransactionsClicked)
                        .disabled(model.transactionCount == 0)
                } footer: {
                    Text(PayeeSettingsModel.listTooltip)
                }
                Section {
                    NavigationLink(value: PayeeRoute.category) {
                        LabeledContent("Kategorie") {
                            Text(verbatim: model.categoryText.isEmpty ? "Keine" : model.categoryText).lineLimit(1)
                        }
                    }
                } header: {
                    Text("Diesen Empfänger automatisch kategorisieren als:").textCase(nil)
                }
                Section {
                    rules
                } header: {
                    Text(TextMarkup.attributed(model.renameIfLabel)).textCase(nil)
                }
            }
            .navigationTitle(model.selectedPayeeName)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.focusRequest?.token, initial: true) { focus = model.focusRequest?.field }
            .alert("Empfänger umbenennen", isPresented: isRenaming) {
                TextField("Name", text: $model.renameText)
                Button("Abbrechen", role: .cancel, action: model.cancelRenaming)
                Button("Umbenennen", action: model.saveRename)
            }
        }

        @ViewBuilder
        private var rules: some View {
            ForEach(model.rules) { rule in
                HStack(spacing: 8) {
                    Picker(
                        "Bedingung",
                        selection: Binding(get: { rule.operator }, set: { model.setOperator(rule.id, $0) })
                    ) {
                        ForEach(StringOperator.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(
                        "Text im Empfänger",
                        text: Binding(get: { rule.operand }, set: { model.setOperand(rule.id, $0) })
                    )
                    .focused($focus, equals: .operand(rule.id))
                    .autocorrectionDisabled()
                }
            }
            .onDelete { offsets in
                for id in offsets.map({ model.rules[$0].id }) { model.removeRule(id) }
            }
            Button("Umbenennungsregel hinzufügen", systemImage: "plus", action: model.addRuleClicked)
                .disabled(model.rules.last?.isBlank ?? false)
            if !model.rules.isEmpty {
                Button("Bestehende Buchungen umbenennen", action: model.renameExistingClicked)
                    .disabled(!model.canRenameExisting)
            }
        }

        private var isRenaming: Binding<Bool> {
            Binding {
                model.isRenaming
            } set: { shown in
                if !shown && model.isRenaming { model.cancelRenaming() }
            }
        }
    }

    private struct PayeeCategoryList: View {
        let model: PayeeSettingsModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ChoiceList(
                title: "Kategorie", choices: model.categoryChoices, current: model.categoryText,
                formatter: model.formatter, showsEmoji: true, noneTitle: "Keine",
                onNewCategory: model.newCategoryClicked, onPick: model.categoryChosen
            )
            // On the list, which stays until the alert is answered.
            .modifier(
                NewCategoryAlert(
                    form: model.addCategoryForm, onCancel: model.addCategoryCancelled,
                    onCreate: { group, name in
                        model.addCategoryConfirmed(masterName: group, name: name)
                        if model.addCategoryForm == nil { dismiss() }
                    }))
        }
    }
#endif
