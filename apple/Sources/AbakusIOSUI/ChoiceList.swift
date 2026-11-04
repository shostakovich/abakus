#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    /// Every row keeps the emoji's column and the check's place, so names and amounts never shift.
    struct ChoiceList: View {
        let title: String
        let choices: (_ search: String) -> [DropDownItem]
        let current: String
        let formatter: BudgetFormatter
        var showsEmoji = false
        var noneTitle: String?
        var initialSearch = ""
        var newPayee: ((_ search: String) -> String?)?
        var onNewCategory: (() -> Void)?
        let onPick: (_ value: String) -> Void
        @State private var search = ""
        @Environment(\.dismiss) private var dismiss
        @ScaledMetric(relativeTo: .body) private var emojiWidth: CGFloat = 28

        var body: some View {
            let sections = HeadedSection.sections(of: choices(search), isHeader: { !$0.isEnabled })
            let leading = showsEmoji ? emojiWidth : nil
            List {
                if let name = newPayee?(search) {
                    Section {
                        Button("Neuer Empfänger „\(name)“", systemImage: "plus") { pick(name) }
                    }
                }
                if let noneTitle, search.isEmpty {
                    Section {
                        Button {
                            pick("")
                        } label: {
                            ChoiceRowLabel(isChosen: current.isEmpty) {
                                ChoiceGlyphText(text: noneTitle, emojiWidth: leading)
                            }
                        }
                        .foregroundStyle(ThemeColor.text)
                    }
                    .listSectionSeparator(.hidden)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { item in
                            Button {
                                pick(item.value)
                            } label: {
                                ChoiceLabel(
                                    item: item, isChosen: item.value == current || item.label == current,
                                    formatter: formatter, emojiWidth: leading)
                            }
                            .foregroundStyle(ThemeColor.text)
                        }
                    } header: {
                        if let header = section.header {
                            ChoiceGlyphText(text: Self.heading(header.label), emojiWidth: leading, isHeading: true)
                                .listRowInsets(.vertical, 4)
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
                if let onNewCategory {
                    Section {
                        Button("Neue Kategorie …", systemImage: "plus", action: onNewCategory)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { search = initialSearch }
        }

        private static func heading(_ label: String) -> String {
            label.hasSuffix(":") ? String(label.dropLast()) : label
        }

        private func pick(_ value: String) {
            onPick(value)
            dismiss()
        }
    }

    /// Flat rows with header rows among them, as runs of rows under their header; a run without rows is dropped.
    struct HeadedSection<Row: Identifiable>: Identifiable where Row.ID == String {
        let id: String
        let header: Row?
        var rows: [Row]

        static func sections(of rows: [Row], isHeader: (Row) -> Bool) -> [HeadedSection] {
            var sections: [HeadedSection] = []
            for row in rows {
                if isHeader(row) {
                    sections.append(HeadedSection(id: row.id, header: row, rows: []))
                } else if sections.isEmpty {
                    sections.append(HeadedSection(id: "top", header: nil, rows: [row]))
                } else {
                    sections[sections.count - 1].rows.append(row)
                }
            }
            return sections.filter { !$0.rows.isEmpty }
        }
    }

    private struct ChoiceGlyphText: View {
        let text: String
        let emojiWidth: CGFloat?
        var isHeading = false

        var body: some View {
            if let emojiWidth {
                let parts = text.leadingEmoji
                HStack(spacing: 6) {
                    Text(verbatim: parts?.emoji ?? "")
                        .font(.body)
                        .frame(width: emojiWidth, alignment: .leading)
                        .accessibilityHidden(true)
                    name(parts?.name ?? text)
                }
            } else {
                name(text)
            }
        }

        @ViewBuilder
        private func name(_ text: String) -> some View {
            if isHeading {
                Text(verbatim: text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ThemeColor.secondaryText)
                    .textCase(nil)
            } else {
                Text(verbatim: text)
            }
        }
    }

    private struct ChoiceLabel: View {
        let item: DropDownItem
        let isChosen: Bool
        let formatter: BudgetFormatter
        let emojiWidth: CGFloat?

        var body: some View {
            ChoiceRowLabel(isChosen: isChosen) {
                if item.kind == .split {
                    if let emojiWidth {
                        HStack(spacing: 6) {
                            Image(systemName: "square.split.2x1")
                                .foregroundStyle(ThemeColor.accent)
                                .frame(width: emojiWidth, alignment: .leading)
                            Text("Aufteilen")
                        }
                    } else {
                        Label("Aufteilen", systemImage: "square.split.2x1")
                    }
                } else if Payee.isTransferPayeeName(item.label) {
                    Label(
                        Payee.transferTargetAccountName(item.label) ?? item.label,
                        systemImage: "arrow.left.arrow.right")
                } else {
                    ChoiceGlyphText(text: item.label, emojiWidth: emojiWidth)
                }
            } trailing: {
                if let balance = item.balance {
                    Text(verbatim: formatter.currency(balance))
                        .monospacedDigit()
                        .foregroundStyle(balance < 0 ? ThemeColor.negative : ThemeColor.secondaryText)
                }
            }
        }
    }

    private struct ChoiceRowLabel<Name: View, Trailing: View>: View {
        let isChosen: Bool
        let name: Name
        let trailing: Trailing
        @ScaledMetric(relativeTo: .body) private var checkWidth: CGFloat = 22

        init(isChosen: Bool, @ViewBuilder name: () -> Name, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
            self.isChosen = isChosen
            self.name = name()
            self.trailing = trailing()
        }

        var body: some View {
            HStack(spacing: 8) {
                name
                Spacer(minLength: 8)
                trailing
                Image(systemName: "checkmark")
                    .foregroundStyle(ThemeColor.accent)
                    .frame(width: checkWidth)
                    .opacity(isChosen ? 1 : 0)
                    .accessibilityHidden(!isChosen)
            }
            .contentShape(Rectangle())
        }
    }

    /// "Neue Kategorie": on a view that stays until it is answered, so a picker's pop can never swallow it.
    struct NewCategoryAlert: ViewModifier {
        let form: AddCategoryForm?
        let onCancel: () -> Void
        let onCreate: (_ groupName: String, _ name: String) -> Void
        @State private var groupName = ""
        @State private var categoryName = ""

        func body(content: Content) -> some View {
            content
                .alert("Neue Kategorie", isPresented: Binding(get: { form != nil }, set: { _ in })) {
                    TextField("Gruppe", text: $groupName)
                    TextField("Name", text: $categoryName)
                    Button("Abbrechen", role: .cancel, action: onCancel)
                    Button("Anlegen") { onCreate(groupName, categoryName) }
                }
                .onChange(of: form) { _, form in
                    groupName = form?.masterName ?? ""
                    categoryName = form?.name ?? ""
                }
        }
    }
#endif
