import AbakusUI
import AppKit
import SwiftUI

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
        let isSorted = sort.column == frame.column
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
