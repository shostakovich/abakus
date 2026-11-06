#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct RegisterList: View {
        static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)

        let register: RegisterViewModel
        let table: RegisterTouchTable?
        /// Where the table's cells start while picking, so the column header can follow the selection circles.
        @Binding var pickingTableLeading: CGFloat
        @State private var listX: CGFloat?

        var body: some View {
            // Sorted by anything but the date, the list has no month headings.
            let sections = HeadedSection.sections(of: register.gridRows, isHeader: \.isMonthHeading)
            ScrollViewReader { proxy in
                List(selection: selection) {
                    ForEach(sections) { section in
                        if let heading = section.header {
                            Section {
                                rows(section.rows)
                            } header: {
                                RegisterMonthHeading(title: heading.title)
                            }
                            .listSectionSeparator(.hidden, edges: .bottom)
                        } else {
                            rows(section.rows)
                        }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(0)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }, action: { listX = $0 })
                .contentMargins(.top, 0, for: .scrollContent)
                .environment(\.defaultMinListHeaderHeight, 0)
                .scrollsUnderDock()
                .environment(\.editMode, .constant(register.isPicking ? .active : .inactive))
                .contextMenu(forSelectionType: String.self) { ids in
                    if !ids.isEmpty {
                        RegisterMenuItemsView(items: register.transactionActionsMenu(for: ids)) {
                            register.performMenuAction($0, on: ids)
                        }
                    }
                } primaryAction: { ids in
                    if ids.count == 1, let id = ids.first { register.beginEditing(id) }
                }
                .onKeyPress(.delete) {
                    register.deleteKeyPressed()
                    return .handled
                }
                .overlay {
                    if sections.isEmpty { emptyState }
                }
                .onChange(of: register.grid.scrollRequest) { _, request in
                    guard let request else { return }
                    switch request.target {
                    case .row(let id): withAnimation { proxy.scrollTo(id) }
                    case .top: proxy.scrollTo(sections.first?.rows.first?.id, anchor: .top)
                    case .bottom: proxy.scrollTo(sections.last?.rows.last?.id, anchor: .bottom)
                    case .offset: break
                    }
                }
            }
        }

        private var emptyState: some View {
            ContentUnavailableView(register.emptyListTitle, systemImage: "list.bullet")
        }

        private func rows(_ rows: [RegisterRow]) -> some View {
            ForEach(rows) { row in
                Group {
                    if let table {
                        RegisterTableRow(register: register, row: row, table: table)
                            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }) { x in
                                if register.isPicking, let listX { pickingTableLeading = x - listX }
                            }
                    } else {
                        RegisterCard(register: register, row: row)
                    }
                }
                // A selected row would turn the default ink white on the light highlight.
                .foregroundStyle(ThemeColor.text)
                .listRowInsets(Self.rowInsets)
                .listRowBackground(isSelected(row) ? SelectedRowFill() : nil)
                .modifier(RegisterRowActions(register: register, row: row))
            }
        }

        private func isSelected(_ row: RegisterRow) -> Bool {
            register.isPicking && !row.isSubtransaction && register.selection.contains(row.transactionId)
        }

        private var selection: Binding<Set<String>> {
            Binding {
                Set(register.selectedTransactionIds)
            } set: { ids in
                register.setSelection(ids)
            }
        }
    }

    /// UIKit keeps a selected row's background through a theme change; a view of its own resolves the fill anew.
    private struct SelectedRowFill: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = UIColor(ThemeColor.selection)
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {}
    }

    private struct RegisterMonthHeading: View {
        let title: String

        var body: some View {
            Text(verbatim: title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ThemeColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RegisterList.rowInsets.leading)
                .padding(.vertical, 5)
                .background(ThemeColor.groupBand)
                .listRowInsets(EdgeInsets())
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Swipes and the context menu take the place of the Mac's right-click.
    struct RegisterRowActions: ViewModifier {
        let register: RegisterViewModel
        let row: RegisterRow

        func body(content: Content) -> some View {
            if row.isSubtransaction {
                content.selectionDisabled()
            } else {
                content
                    .tag(row.transactionId)
                    .swipeActions(edge: .trailing) {
                        // Without the destructive role, so a delete that asks or is refused leaves the row in place.
                        Button("Löschen", systemImage: "trash") {
                            register.performMenuAction(.delete, on: [row.transactionId])
                        }
                        .tint(ThemeColor.negative)
                    }
            }
        }
    }
#endif
