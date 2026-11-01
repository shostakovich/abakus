import AppKit
import SwiftUI

enum RegisterGridStyle {
    static let headerFont = ThemeFont(size: NSFont.smallSystemFontSize, weight: .medium)
    static let rowFont = ThemeFont.table
    static let rowBoldFont = ThemeFont.tableEmphasized
    static let monthHeadingFont = ThemeFont(size: NSFont.smallSystemFontSize, weight: .semibold)
    static let symbolSize: CGFloat = 13
    static let cellInset: CGFloat = 6
    static let sortIndicatorWidth: CGFloat = 12
    static let subRowIndent: CGFloat = 14
    static let addedRowCanvas = ThemeColor.accent.opacity(0.15)
    static let adjustmentRow = ThemeColor.accent.opacity(0.15)
    static let addedRowGlow = ThemeColor.accent
}

extension RegisterColumn {
    /// The wider of the header and the widest cell plus `accessory`, never under the column's minimum.
    func contentWidth(fitting texts: [String], accessory: CGFloat = 0) -> CGFloat {
        let headerWidth: CGFloat =
            switch header {
            case .text(let title): RegisterGridStyle.headerFont.width(of: title) + RegisterGridStyle.sortIndicatorWidth
            case .symbol: 0
            }
        let cellWidth = texts.map { RegisterGridStyle.rowFont.width(of: $0) + accessory }.max() ?? 0
        return max(minWidth, ceil(max(headerWidth, cellWidth) + 2 * RegisterGridStyle.cellInset))
    }
}

struct RegisterGridHeader: View {
    let owner: any RegisterGridOwner
    let layout: RegisterColumnLayout

    var body: some View {
        let sort = owner.sortOrder
        ZStack(alignment: .topLeading) {
            ForEach(layout.frames, id: \.column) { frame in
                RegisterHeaderCell(frame: frame, sort: sort) { owner.grid.headerClicked(frame.column) }
                    .offset(x: frame.x)
            }
            ColumnOptionsButton(action: owner.columnOptionsClicked)
                .registerAnchor(owner.columnTab)
                .offset(x: layout.displayWidth)
        }
        .frame(width: layout.gridWidth, height: RegisterMetrics.headerHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct RegisterHeaderCell: View {
    let frame: RegisterColumnFrame
    let sort: RegisterSortOrder
    let action: () -> Void

    var body: some View {
        let isSorted = frame.column.isSortable && sort.column == frame.column
        Button(action: action) {
            label(isSorted: isSorted)
                .padding(.horizontal, RegisterGridStyle.cellInset)
                .frame(width: frame.width, height: RegisterMetrics.headerHeight, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSorted ? .isSelected : [])
    }

    private var alignment: Alignment {
        switch frame.column.header {
        case .symbol: .center
        case .text: frame.column.isAmount ? .trailing : .leading
        }
    }

    private func label(isSorted: Bool) -> some View {
        HStack(spacing: 3) {
            switch frame.column.header {
            case .text(let title):
                Text(verbatim: title).lineLimit(1)
            case .symbol(let name, let label):
                Image(systemName: name).accessibilityLabel(label)
            }
            if isSorted {
                Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel(sort.ascending ? "Aufsteigend sortiert" : "Absteigend sortiert")
            }
        }
        .font(RegisterGridStyle.headerFont.font)
        .foregroundStyle(isSorted ? ThemeColor.text : ThemeColor.secondaryText)
    }
}

struct ColumnOptionsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(RegisterGridStyle.headerFont.font)
                .foregroundStyle(ThemeColor.secondaryText)
                .frame(width: RegisterMetrics.columnMenuWidth, height: RegisterMetrics.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spalten")
        .toolTip("Spalten")
    }
}
