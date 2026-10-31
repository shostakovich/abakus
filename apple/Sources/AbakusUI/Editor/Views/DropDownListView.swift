import AbakusCore
import SwiftUI

@MainActor
protocol DropDownListHost: AnyObject {
    func dropDownRowHovered(_ index: Int?)
    func dropDownRowClicked(_ index: Int)
    func dropDownFooterClicked()
}

extension TransactionEditor: DropDownListHost {}

struct DropDownListView: View {
    static let rowHeight = SystemChrome.menuRowHeight
    static let promptRowHeight: CGFloat = 54
    static let padding = SystemChrome.menuPadding
    static let separatorHeight: CGFloat = 11

    let editor: any DropDownListHost
    let state: DropDownState
    let width: CGFloat
    let formatter: BudgetFormatter

    static func height(_ state: DropDownState) -> CGFloat {
        let rows = state.items.prefix(state.kind.rowCount).reduce(CGFloat(0)) { $0 + rowHeight(of: $1) }
        let header: CGFloat = state.kind.headerTitle == nil ? 0 : rowHeight
        let footer: CGFloat = state.footerTitle == nil ? 0 : separatorHeight + rowHeight
        return 2 * padding + header + rows + footer
    }

    static func rowHeight(of item: DropDownItem) -> CGFloat {
        item.kind == .prompt ? promptRowHeight : rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title = state.kind.headerTitle {
                MenuSectionTitle(title: title)
            }
            rows
            footer
        }
        .padding(.vertical, Self.padding)
        .frame(width: width)
        .font(ThemeFont.body.font)
        .systemMenuChrome()
        .floatingShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.kind.headerTitle ?? "Vorschläge")
    }

    private var rows: some View {
        let visible = state.items.prefix(state.kind.rowCount).reduce(CGFloat(0)) { $0 + Self.rowHeight(of: $1) }
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        DropDownRow(
                            item: item, isHighlighted: state.highlighted == index, kind: state.kind,
                            formatter: formatter
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onHover { inside in editor.dropDownRowHovered(inside ? index : nil) }
                        .onTapGesture { editor.dropDownRowClicked(index) }
                    }
                }
            }
            .scrollIndicators(state.items.count > state.kind.rowCount ? .visible : .never)
            .frame(height: visible)
            .onAppear { scroll(proxy) }
            .onChange(of: state.scrollToken) { scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if let item = state.highlightedItem {
            proxy.scrollTo(item.id)
        } else if let first = state.items.first {
            proxy.scrollTo(first.id, anchor: .top)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let title = state.footerTitle {
            Divider()
                .padding(.horizontal, 10)
                .frame(height: Self.separatorHeight)
            FooterItem(
                title: title, systemImage: state.kind == .payee ? "pencil" : "plus",
                action: editor.dropDownFooterClicked)
        }
    }
}

private struct MenuSectionTitle: View {
    let title: String
    var hasSeparator = false

    var body: some View {
        Text(verbatim: title)
            .font(ThemeFont.caption.font.weight(.semibold))
            .foregroundStyle(ThemeColor.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 10 + DropDownListView.padding)
            .frame(maxWidth: .infinity, minHeight: DropDownListView.rowHeight, alignment: .leading)
            .overlay(alignment: .top) {
                if hasSeparator { Divider().padding(.horizontal, 10) }
            }
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FooterItem: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(isHovered ? ThemeColor.selectedText : ThemeColor.secondaryText)
                .frame(width: 16)
            Text(verbatim: title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHovered ? ThemeColor.selectedText : ThemeColor.text)
        .padding(.horizontal, 10)
        .frame(height: DropDownListView.rowHeight)
        .background {
            if isHovered { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
        }
        .padding(.horizontal, DropDownListView.padding)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct DropDownRow: View {
    static let categoryIndent: CGFloat = 12

    let item: DropDownItem
    let isHighlighted: Bool
    let kind: DropDownKind
    let formatter: BudgetFormatter

    var body: some View {
        switch item.kind {
        case .transfersHeader, .accountHeader:
            MenuSectionTitle(title: item.label, hasSeparator: true)
        case .masterHeader:
            MenuSectionTitle(title: item.label, hasSeparator: item.drawTopBorder)
        case .prompt:
            Text(verbatim: item.label)
                .foregroundStyle(ThemeColor.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: DropDownListView.promptRowHeight)
        default:
            selectableRow
        }
    }

    private var selectableRow: some View {
        HStack(spacing: 6) {
            if item.kind == .split {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(isHighlighted ? ThemeColor.selectedText : ThemeColor.secondaryText)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            Text(verbatim: item.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let balance = item.balance {
                Text(verbatim: formatter.currency(balance))
                    .font(ThemeFont.table.font)
                    .foregroundStyle(balanceStyle(balance))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isHighlighted ? ThemeColor.selectedText : ThemeColor.text)
        .padding(.leading, isCategory ? 10 + Self.categoryIndent : 10)
        .padding(.trailing, 10)
        .frame(height: DropDownListView.rowHeight)
        .background {
            if isHighlighted { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
        }
        .padding(.horizontal, DropDownListView.padding)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private var isCategory: Bool {
        if case .category = item.kind { return true }
        return false
    }

    private func balanceStyle(_ balance: Decimal) -> AnyShapeStyle {
        if isHighlighted { return AnyShapeStyle(ThemeColor.selectedText) }
        if balance < 0 { return AnyShapeStyle(ThemeColor.negative) }
        return balance == 0 ? AnyShapeStyle(ThemeColor.tertiaryText) : AnyShapeStyle(ThemeColor.secondaryText)
    }
}
