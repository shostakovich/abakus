#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct ScheduledSheet: View {
        let register: RegisterViewModel
        let dialogs: [PresentedDialog]
        /// The presenter's width class: inside the sheet it can turn compact on the iPad, whose sheet fits its list.
        let isCompact: Bool

        /// About as many rows as the phone's medium detent shows.
        private static let rowsAtMediumDetent = 4

        private var scheduler: RegisterScheduler { register.scheduler }

        var body: some View {
            let editor = scheduler.editor
            let rowCount = scheduler.rows.filter { !$0.isSubtransaction }.count
            NavigationStack {
                list
                    .navigationTitle(RegisterScheduler.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(
                                "Schließen", systemImage: "xmark", role: .close, action: register.scheduledToggleClicked
                            )
                        }
                        ToolbarItem(placement: .primaryAction) { addButton }
                    }
            }
            .modifier(FittedFormSheet(minimumHeight: rowCount == 0 ? 360 : 0))
            .modifier(PhoneDetents(isOn: isCompact, startsAtMedium: rowCount <= Self.rowsAtMediumDetent))
            .presentationBackground(ThemeColor.groupedBackground)
            .sheet(isPresented: editorSheet(editor != nil)) {
                if let editor {
                    TransactionSheet(editor: editor, dialogs: dialogs).id(ObjectIdentifier(editor))
                }
            }
            .modifier(DialogAlert(dialogs: editor == nil ? dialogs : []))
        }

        private var list: some View {
            let rows = scheduler.rows.filter { !$0.isSubtransaction }
            return List {
                ForEach(rows) { row in
                    ScheduledRow(scheduler: scheduler, row: row, showsAccount: register.isAllAccounts)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ThemeColor.groupedBackground)
            .modifier(ReportsFormHeight())
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        RegisterScheduler.emptyTitle, systemImage: "calendar",
                        description: Text(RegisterScheduler.emptyMessage))
                }
            }
        }

        private var addButton: some View {
            Button(RegisterScheduler.addTitle, systemImage: "plus", action: scheduler.addClicked)
                .disabled(!scheduler.canAddTransactions)
        }

        private func editorSheet(_ isShown: Bool) -> Binding<Bool> {
            Binding {
                isShown
            } set: { shown in
                if !shown { scheduler.editor?.cancel() }
            }
        }
    }

    private struct PhoneDetents: ViewModifier {
        let isOn: Bool
        let startsAtMedium: Bool

        func body(content: Content) -> some View {
            if isOn {
                content
                    .presentationDetents(startsAtMedium ? [.medium, .large] : [.large])
                    .presentationDragIndicator(.visible)
            } else {
                content
            }
        }
    }

    private struct ScheduledRow: View {
        let scheduler: RegisterScheduler
        let row: RegisterRow
        let showsAccount: Bool

        var body: some View {
            let ids: Set<String> = [row.transactionId]
            Button {
                scheduler.beginEditing(row.transactionId)
            } label: {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                RegisterMenuItemsView(items: scheduler.actionsMenu(for: ids)) {
                    scheduler.performMenuAction($0, on: ids)
                }
            }
            .swipeActions(edge: .leading) {
                if scheduler.canEnter(ids) {
                    Button(RegisterScheduler.enterTitle, systemImage: "checkmark") { perform(.enterScheduledNow) }
                        .tint(ThemeColor.accent)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(RegisterScheduler.deleteTitle.touchLabel, systemImage: "trash") { perform(.deleteScheduled) }
                    .tint(ThemeColor.negative)
                Button(RegisterScheduler.skipTitle, systemImage: "forward") { perform(.skipScheduled) }
                    .tint(ThemeColor.warning)
            }
        }

        private var card: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RegisterPayeeText(row: row)
                    Spacer(minLength: 8)
                    RegisterAmountText(row: row)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: summary)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: details)
                        .monospacedDigit()
                        .foregroundStyle(ThemeColor.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.subheadline)
            }
        }

        private var summary: String {
            [row.category, row.memo].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        private var details: String {
            ((showsAccount ? [row.account] : []) + [row.repeatLabel, row.date]).joined(separator: " · ")
        }

        private func perform(_ action: RegisterMenuAction) {
            scheduler.performMenuAction(action, on: [row.transactionId])
        }
    }
#endif
