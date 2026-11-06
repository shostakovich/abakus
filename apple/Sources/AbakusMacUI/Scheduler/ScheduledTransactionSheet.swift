import AbakusCore
import AbakusUI
import SwiftUI

/// A scheduled transaction's sheet, opened by „+“ or a double click: what it books, then when.
struct ScheduledTransactionSheet: View {
    let scheduler: RegisterScheduler
    let editor: TransactionEditor
    @FocusState private var focus: EditorFieldID?

    var body: some View {
        let deletes = editor.mode == .existing
        FormSheet(
            title: editor.sheetTitle, note: editor.followingDatesText,
            destructive: deletes
                ? FormSheetAction(title: RegisterScheduler.deleteTitle, action: scheduler.deleteEditedClicked) : nil,
            confirmTitle: EditorButton.save.title,
            onConfirm: {
                focus = nil
                editor.activate(editor.sheetConfirmButton)
            },
            onCancel: { editor.activate(.cancel) }
        ) {
            Section {
                accountRow
                FormSheetRow("Empfänger") { PayeeField(editor: editor, focus: $focus) }
                if editor.showsCategory {
                    FormSheetRow("Kategorie") { CategoryMenu(editor: editor, field: .main(.category)) }
                }
                FormSheetRow("Memo") { SheetTextField(editor: editor, field: .main(.memo), focus: $focus) }
                FormSheetRow("Betrag") { AmountField(editor: editor, field: .main(.amount), focus: $focus) }
            }
            if editor.isSplitMode {
                Section("Teile") { SplitParts(editor: editor, focus: $focus) }
            }
            Section {
                FormSheetRow("Nächstes Datum") { dateField }
                FormSheetRow("Wiederholen") {
                    Picker(
                        "Wiederholen",
                        selection: Binding(
                            get: { editor.repeatChoice ?? .monthly }, set: { editor.repeatChosen($0) })
                    ) {
                        ForEach(Repeat.Choice.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if editor.showsCustomRepeat {
                    FormSheetRow("Alle") { CustomRepeatFields(editor: editor) }
                }
            }
        }
        .defaultFocus($focus, editor.mode == .new ? .main(.payee) : nil)
        .onChange(of: focus) { old, new in
            if let new {
                editor.sheetFieldFocused(new)
            } else if let old {
                editor.sheetFieldUnfocused(old)
            }
        }
        .sheet(item: Binding(get: { editor.addCategoryRequest }, set: { _ in })) { request in
            AddCategorySheet(request: request)
        }
    }

    @ViewBuilder private var accountRow: some View {
        let field = EditorFieldID.main(.account)
        FormSheetRow("Konto") {
            if editor.choosesAccount && !editor.isLocked(field) {
                ChoiceMenu(
                    editor: editor, field: field, current: editor.text(field),
                    groups: ChoiceGroup.accounts(editor.choices(for: field, matching: "")))
            } else {
                Text(verbatim: editor.text(field))
            }
        }
    }

    private var dateField: some View {
        let calendar = editor.formatter.dateLocale.calendar
        let range = editor.pickableDates
        let date = Binding(get: { editor.clone.date }, set: { editor.datePicked($0) })
        return HStack(spacing: 8) {
            DatePicker(
                "Nächstes Datum",
                selection: Binding(
                    get: { editor.clone.date.date(in: calendar) },
                    set: { editor.datePicked(DateWithoutTime($0, in: calendar)) }),
                in: range.lowerBound.date(in: calendar)...range.upperBound.date(in: calendar),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .environment(\.locale, Locale(identifier: editor.formatter.dateLocale.identifier))
            CalendarPopoverButton(date: date, locale: editor.formatter.dateLocale)
        }
    }
}

/// The sheet's text fields tell the editor what they hold; leaving one commits it as in the register.
private struct SheetTextField: View {
    let editor: TransactionEditor
    let field: EditorFieldID
    var focus: FocusState<EditorFieldID?>.Binding
    var prompt: String?
    var alignment = TextAlignment.leading

    var body: some View {
        TextField(
            editor.prompt(field),
            text: Binding(get: { editor.text(field) }, set: { editor.sheetTextChanged(field, to: $0) }),
            prompt: Text(prompt ?? "Optional")
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(alignment)
        .focused(focus, equals: field)
        .disabled(editor.isLocked(field))
    }
}

/// Typing offers the known payees and the accounts to transfer to, as the register's list does.
private struct PayeeField: View {
    let editor: TransactionEditor
    var focus: FocusState<EditorFieldID?>.Binding

    var body: some View {
        let field = EditorFieldID.main(.payee)
        SheetTextField(editor: editor, field: field, focus: focus, prompt: "Empfänger")
            .textInputSuggestions {
                ForEach(suggestions(field)) { item in
                    if case .transfer = item.kind {
                        Label(item.label, systemImage: StatusSymbol.transfer.name).textInputCompletion(item.value)
                    } else {
                        Text(verbatim: item.label).textInputCompletion(item.value)
                    }
                }
            }
    }

    private func suggestions(_ field: EditorFieldID) -> [DropDownItem] {
        editor.choices(for: field, matching: editor.text(field)).filter { item in
            switch item.kind {
            case .payee, .transfer: true
            default: false
            }
        }
    }
}

private struct AmountField: View {
    let editor: TransactionEditor
    let field: EditorFieldID
    var focus: FocusState<EditorFieldID?>.Binding

    var body: some View {
        let isInflow = editor.isInflow(field)
        HStack(spacing: 6) {
            Button {
                editor.sheetSignToggled(field)
            } label: {
                Image(systemName: isInflow ? "plus" : "minus")
                    .foregroundStyle(isInflow ? ThemeColor.positive : ThemeColor.text)
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            .disabled(editor.isLocked(field))
            .accessibilityLabel(isInflow ? "Einnahme" : "Ausgabe")
            .help(isInflow ? "Macht eine Ausgabe daraus" : "Macht eine Einnahme daraus")
            SheetTextField(editor: editor, field: field, focus: focus, prompt: "0,00", alignment: .trailing)
                .monospacedDigit()
        }
    }
}

private struct CategoryMenu: View {
    let editor: TransactionEditor
    let field: EditorFieldID

    var body: some View {
        let value = editor.sheetValue(field).text
        ChoiceMenu(
            editor: editor, field: field, current: value.isEmpty ? editor.prompt(field) : value,
            groups: ChoiceGroup.categories(editor.choices(for: field, matching: "")),
            onNewCategory: { editor.addCategoryClicked(for: field) })
    }
}

/// A pop-up of the editor's choices for a field; picking one commits it as a click in the register's list does.
private struct ChoiceMenu: View {
    let editor: TransactionEditor
    let field: EditorFieldID
    let current: String
    let groups: [ChoiceGroup]
    var onNewCategory: (() -> Void)?

    var body: some View {
        Menu {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        Button(item.label) { editor.choose(item.value, for: field) }
                    }
                }
            }
            if let onNewCategory {
                Divider()
                Button("Neue Kategorie …", action: onNewCategory)
            }
        } label: {
            Text(verbatim: current).lineLimit(1)
        }
        .fixedSize()
        .disabled(editor.isLocked(field))
    }
}

private struct ChoiceGroup: Identifiable {
    var id: String
    var title: String
    var items: [DropDownItem] = []

    static func categories(_ items: [DropDownItem]) -> [ChoiceGroup] {
        var groups: [ChoiceGroup] = []
        for item in items {
            switch item.kind {
            case .split: groups.append(ChoiceGroup(id: item.id, title: "", items: [item]))
            case .masterHeader: groups.append(ChoiceGroup(id: item.id, title: item.label))
            case .category where !groups.isEmpty: groups[groups.count - 1].items.append(item)
            default: break
            }
        }
        return groups.filter { !$0.items.isEmpty }
    }

    static func accounts(_ items: [DropDownItem]) -> [ChoiceGroup] {
        var groups = [ChoiceGroup(id: "accounts", title: "")]
        for item in items {
            switch item.kind {
            case .accountHeader: groups.append(ChoiceGroup(id: item.id, title: item.label))
            case .account: groups[groups.count - 1].items.append(item)
            default: break
            }
        }
        return groups.filter { !$0.items.isEmpty }
    }
}

private struct SplitParts: View {
    let editor: TransactionEditor
    var focus: FocusState<EditorFieldID?>.Binding

    var body: some View {
        ForEach(editor.subIds, id: \.self) { id in
            HStack(spacing: 8) {
                CategoryMenu(editor: editor, field: .sub(id, .category))
                    .frame(maxWidth: 160, alignment: .leading)
                SheetTextField(editor: editor, field: .sub(id, .memo), focus: focus, prompt: "Memo")
                AmountField(editor: editor, field: .sub(id, .amount), focus: focus).frame(width: 130)
                Button {
                    if focus.wrappedValue?.subId == id { focus.wrappedValue = nil }
                    editor.deleteSubRow(id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Teil löschen")
            }
        }
        HStack {
            Button("Teil hinzufügen", systemImage: "plus") { editor.addSplitLine() }
                .buttonStyle(.borderless)
            Spacer(minLength: 8)
            Text("Noch aufzuteilen")
                .foregroundStyle(.secondary)
            Text(verbatim: editor.remainingText)
                .monospacedDigit()
                .foregroundStyle(editor.remainingAmount == 0 ? ThemeColor.secondaryText : ThemeColor.negative)
        }
    }
}

/// Eigene: a count from 1 to 99 and Wochen or Monate.
private struct CustomRepeatFields: View {
    let editor: TransactionEditor

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                "Anzahl",
                text: Binding(
                    get: { String(editor.customCount) },
                    set: { text in if let count = Int(text) { editor.repeatCountChosen(count) } })
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 44)
            Picker(
                "Einheit",
                selection: Binding(get: { editor.customUnit }, set: { editor.repeatUnitChosen($0) })
            ) {
                ForEach(Repeat.Unit.allCases, id: \.self) { unit in
                    Text(TransactionEditor.unitLabel(unit, count: editor.customCount)).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}
