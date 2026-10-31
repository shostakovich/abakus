import AbakusCore
import SwiftUI

struct PayeeSettingsSheet: View {
    static let size = CGSize(width: 780, height: 560)
    static let listWidth: CGFloat = 240

    @Bindable var model: PayeeSettingsModel
    @FocusState private var focus: PayeeSettingsModel.Field?
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(PayeeSettingsModel.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)
            HStack(spacing: 0) {
                PayeeList(model: model, isFocused: $isListFocused)
                    .frame(width: Self.listWidth)
                    .padding(.leading, 20)
                    .padding(.vertical, 12)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            AutoFillBar(model: model)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlayPreferenceValue(PayeeCategoryAnchorKey.self) { anchor in
            CategorySuggestions(model: model, anchor: anchor)
        }
        // The key press reaches SwiftUI-focused views; the exit command covers AppKit responders.
        .onKeyPress(.escape) {
            model.escapePressed()
            return .handled
        }
        .onExitCommand(perform: model.escapePressed)
        .defaultFocus($isListFocused, true)
        .onAppear { focus = model.focusRequest?.field }
        .onChange(of: model.focusRequest?.token) { focus = model.focusRequest?.field }
        .onChange(of: focus) { old, new in
            if old == .category && new != .category { model.categoryFocusLost() }
            if new == .category && old != .category { model.categoryFocused() }
        }
        .sheet(item: Binding(get: { model.addCategoryRequest }, set: { _ in })) { request in
            AddCategorySheet(request: request)
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var detail: some View {
        switch model.state {
        case .noSelection:
            Text(PayeeSettingsModel.selectPrompt)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .single:
            SinglePayeeForm(model: model, focus: $focus)
        case .multiple:
            MultiplePayeesForm(model: model, focus: $focus)
        }
    }
}

private struct PayeeList: View {
    let model: PayeeSettingsModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        let selection = Binding(get: { Set(model.selection) }, set: { model.selectionChanged(to: $0) })
        ScrollViewReader { proxy in
            List(model.rows, selection: selection) { row in
                PayeeRow(row: row)
            }
            .listStyle(.bordered)
            .focused(isFocused)
            .accessibilityLabel("Empfänger")
            .onAppear { scrollToRequest(proxy) }
            .onChange(of: model.scrollRequest?.token) { scrollToRequest(proxy) }
        }
    }

    private func scrollToRequest(_ proxy: ScrollViewProxy) {
        guard let id = model.scrollRequest?.payeeId else { return }
        proxy.scrollTo(id, anchor: .top)
    }
}

private struct PayeeRow: View {
    let row: PayeeSettingsModel.Row

    var body: some View {
        HStack(spacing: 6) {
            Text(row.name)
                .fontWeight(row.hasRules ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.name)
            Spacer(minLength: 0)
            if !row.isEnabled {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help(PayeeSettingsModel.disabledTooltip)
                    .accessibilityLabel("Ausgeblendet")
            }
        }
    }
}

private struct SinglePayeeForm: View {
    @Bindable var model: PayeeSettingsModel
    var focus: FocusState<PayeeSettingsModel.Field?>.Binding

    var body: some View {
        Form {
            Section {
                if model.isRenaming { renameRow } else { nameRow }
                listingRow
            }
            Section {
                CategoryField(model: model, focus: focus)
            } header: {
                Text("Diesen Empfänger automatisch kategorisieren als:").fontWeight(.regular)
            }
            Section {
                if model.rules.isEmpty {
                    Button("Umbenennungsregel hinzufügen", systemImage: "plus", action: model.addRuleClicked)
                } else {
                    ForEach(model.rules) { rule in RuleRowView(model: model, rule: rule, focus: focus) }
                }
            } header: {
                Text(TextMarkup.attributed(model.renameIfLabel)).fontWeight(.regular)
            } footer: {
                if !model.rules.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Bestehende Buchungen umbenennen", action: model.renameExistingClicked)
                            .disabled(!model.canRenameExisting)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var nameRow: some View {
        HStack(spacing: 8) {
            Text(model.selectedPayeeName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.selectedPayeeName)
                .onTapGesture(perform: model.startRenaming)
            Spacer(minLength: 0)
            if !model.isTransfer {
                Button("Umbenennen", systemImage: "pencil", action: model.startRenaming)
            }
        }
    }

    private var renameRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $model.renameText)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Name des Empfängers")
                .focused(focus, equals: .rename)
                .onSubmit(model.saveRename)
            Button("Abbrechen", action: model.cancelRenaming)
            Button("Sichern", action: model.saveRename)
        }
    }

    private var listingRow: some View {
        LabeledContent {
            Toggle(
                "Empfänger aufführen und ergänzen",
                isOn: Binding(get: { model.isSelectedPayeeEnabled }, set: { model.setSelectedPayeeEnabled($0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(model.isTransfer)
        } label: {
            Text("Empfänger aufführen und ergänzen")
            Text(usage)
                .help(model.transactionCount > 0 ? "Klicken, um diese Buchungen im Konto zu zeigen" : "")
                .environment(
                    \.openURL,
                    OpenURLAction { _ in
                        model.showTransactionsClicked()
                        return .handled
                    })
        }
        .help(PayeeSettingsModel.listTooltip)
    }

    private var usage: AttributedString {
        var count = AttributedString(model.transactionCountText)
        if model.transactionCount > 0 { count.link = URL(string: "abakus:payee-transactions") }
        return AttributedString("(in ") + count + AttributedString(")")
    }
}

private struct CategoryField: View {
    let model: PayeeSettingsModel
    var focus: FocusState<PayeeSettingsModel.Field?>.Binding

    var body: some View {
        let text = Binding(get: { model.categoryText }, set: { model.categoryTextChanged($0) })
        HStack(spacing: 6) {
            TextField("", text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Kategorie")
                .focused(focus, equals: .category)
                .onSubmit(model.commitCategory)
                .onKeyPress(.upArrow) {
                    model.moveCategoryHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.moveCategoryHighlight(by: 1)
                    return .handled
                }
            Button(action: model.categoryButtonClicked) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kategorien")
        }
        .anchorPreference(key: PayeeCategoryAnchorKey.self, value: .bounds) { $0 }
    }
}

private struct RuleRowView: View {
    let model: PayeeSettingsModel
    let rule: PayeeSettingsModel.RuleRow
    var focus: FocusState<PayeeSettingsModel.Field?>.Binding

    var body: some View {
        let isLast = model.isLastRule(rule.id)
        HStack(spacing: 8) {
            Picker("Bedingung", selection: Binding(get: { rule.operator }, set: { model.setOperator(rule.id, $0) })) {
                ForEach(StringOperator.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .frame(width: 120, alignment: .leading)
            TextField("", text: Binding(get: { rule.operand }, set: { model.setOperand(rule.id, $0) }))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Text im Empfänger")
                .focused(focus, equals: .operand(rule.id))
            Button("Regel entfernen", systemImage: "minus") { model.removeRule(rule.id) }
                .labelStyle(.iconOnly)
            Button("Umbenennungsregel hinzufügen", systemImage: "plus", action: model.addRuleClicked)
                .labelStyle(.iconOnly)
                .disabled(rule.isBlank)
                .opacity(isLast ? 1 : 0)
                .allowsHitTesting(isLast)
                .accessibilityHidden(!isLast)
        }
    }
}

private struct MultiplePayeesForm: View {
    @Bindable var model: PayeeSettingsModel
    var focus: FocusState<PayeeSettingsModel.Field?>.Binding

    var body: some View {
        Form {
            Section(model.multipleTitle) {
                Text(model.selectedNamesText)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .help(model.selectedNamesText)
            }
            Section {
                LabeledContent("Neuer Name") {
                    HStack(spacing: 8) {
                        TextField("", text: $model.combineName)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Neuer Name")
                            .focused(focus, equals: .combine)
                            .onSubmit(model.combineClicked)
                        Button("Zusammenfassen", action: model.combineClicked)
                            .disabled(!model.canCombine)
                    }
                }
            } header: {
                Text("Ausgewählte Empfänger zusammenfassen und umbenennen?").help(PayeeSettingsModel.combineTooltip)
            }
            Section {
                HStack(spacing: 8) {
                    Button("Ausblenden") { model.setSelectedPayeesEnabled(false) }
                    Button("Aufführen") { model.setSelectedPayeesEnabled(true) }
                }
            } header: {
                Text("Ausgewählte Empfänger aufführen und ergänzen?").help(PayeeSettingsModel.listTooltip)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AutoFillBar: View {
    let model: PayeeSettingsModel

    var body: some View {
        HStack(spacing: 16) {
            Text("Ergänzen (alle Empfänger):")
            Toggle("Kategorie", isOn: setting(\.category))
                .help("Neue Buchungen bekommen die Kategorie, die beim Empfänger hinterlegt ist.")
            Toggle("Memo", isOn: setting(\.memo))
                .help("Neue Buchungen bekommen das Memo, das zuletzt mit dem Empfänger verwendet wurde.")
            Toggle("Betrag", isOn: setting(\.amount))
                .help("Neue Buchungen bekommen den Betrag, der zuletzt mit dem Empfänger verwendet wurde.")
            Spacer(minLength: 0)
            Button("Schließen", action: model.close)
        }
        .toggleStyle(.checkbox)
        .padding(20)
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

/// Drawn over the whole sheet so the form does not clip the suggestions.
private struct CategorySuggestions: View {
    let model: PayeeSettingsModel
    let anchor: Anchor<CGRect>?

    var body: some View {
        GeometryReader { proxy in
            if let list = model.categoryList, let anchor {
                let frame = proxy[anchor]
                DropDownListView(
                    editor: model, state: list, width: max(frame.width, DropDownKind.category.minWidth),
                    formatter: model.formatter
                )
                .offset(x: frame.minX, y: frame.maxY + 4)
            }
        }
    }
}

private struct PayeeCategoryAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
