import AbakusCore
import SwiftUI

struct BudgetCategoryHeaderCell: View {
    let model: BudgetViewModel
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "Kategorie")
                .font(BudgetStyle.columnTitleFont.font)
                .foregroundStyle(ThemeColor.secondaryText)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button(action: model.addMasterCategoryClicked) {
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text(verbatim: "Gruppe").font(BudgetStyle.columnTitleFont.font)
                }
                .foregroundStyle(ThemeColor.text)
                .frame(height: BudgetSymbolButton.size)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Neue Kategoriegruppe")
            .toolTip("Neue Kategoriegruppe")
            BudgetSymbolButton(
                symbol: "chevron.down", label: "Alle Gruppen aufklappen", toolTip: "Alle Gruppen aufklappen",
                action: model.expandAllClicked)
            BudgetSymbolButton(
                symbol: "chevron.up", label: "Alle Gruppen zuklappen", toolTip: "Alle Gruppen zuklappen",
                action: model.collapseAllClicked)
        }
        .padding(.leading, BudgetMetrics.cellPadding)
        .padding(.trailing, 4)
        .padding(.bottom, BudgetStyle.columnHeadBottomPadding)
        .frame(width: width, height: height, alignment: .bottom)
    }
}

struct BudgetCategoryRowsView: View {
    let model: BudgetViewModel
    let width: CGFloat

    var body: some View {
        BudgetGroupsStack(groups: model.groups, offset: model.scrollOffset) { group in
            BudgetCategoryHeaderRow(model: model, group: group, width: width)
        } sub: { row in
            BudgetCategorySubRow(model: model, row: row, width: width)
        }
    }
}

private struct BudgetRowDrag: ViewModifier {
    let model: BudgetViewModel
    let rowId: String
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: BudgetMetrics.dragThreshold, coordinateSpace: .named(BudgetView.panelSpace))
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { value in
                    if model.drag == nil {
                        model.dragPressed(rowId: rowId, at: model.rowsPoint(value.startLocation))
                    }
                    model.dragMoved(
                        to: model.rowsPoint(value.location),
                        edgeDepth: BudgetViewModel.autoScrollDepth(
                            windowY: value.location.y, windowHeight: model.panelSize.height))
                }
                .onEnded { _ in model.dragReleased() }
        )
        .onChange(of: isDragging) { _, dragging in
            if !dragging { model.dragCancelled() }
        }
    }
}

private struct BudgetCategoryName: View {
    let model: BudgetViewModel
    let row: BudgetCategoryRow
    let font: ThemeFont
    var isProxy = false
    @State private var isHovered = false

    var body: some View {
        Text(verbatim: row.name)
            .font(font.font)
            .foregroundStyle(ThemeColor.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .underline(isHovered || isProxy)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { model.present(.editCategory(categoryId: row.id)) }
            .pointerStyle(.link)
            .toolTip(row.nameToolTip)
            .accessibilityAddTraits(.isButton)
    }
}

struct BudgetCategoryHeaderRow: View {
    let model: BudgetViewModel
    let group: BudgetGroup
    let width: CGFloat
    var isProxy = false

    private var row: BudgetCategoryRow { group.header }

    var body: some View {
        let isPointerOver = !isProxy && model.hoveredRowId == row.id
        HStack(spacing: 2) {
            leading
            name
            Spacer(minLength: 0)
            if row.kind == .master && isPointerOver {
                BudgetSymbolButton(
                    symbol: "plus.circle", label: "Kategorie in \(row.name) hinzufügen", toolTip: "Kategorie hinzufügen"
                ) { model.addSubCategoryClicked(masterId: row.id) }
            }
        }
        .padding(.trailing, 6)
        .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .leading)
        .background {
            if isProxy { Rectangle().fill(ThemeColor.groupFill).background(ThemeColor.contentBackground) }
        }
        .contentShape(Rectangle())
        .onHover { model.rowHovered(row.id, $0) }
        .budgetPopupAnchor(.categoryRow(row.id), of: model)
        .modifier(BudgetRowDragIfMaster(model: model, row: row))
    }

    @ViewBuilder
    private var leading: some View {
        switch row.kind {
        case .master:
            Button {
                model.disclosureClicked(row.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThemeColor.secondaryText)
                    .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                    .frame(width: 20, height: BudgetMetrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(group.isExpanded ? "Zuklappen" : "Aufklappen")
            .padding(.leading, BudgetStyle.nameX - 22)
        case .uncategorized:
            Image(systemName: StatusSymbol.warning)
                .font(.system(size: BudgetStyle.symbolSize))
                .foregroundStyle(ThemeColor.warning)
                .frame(width: 20)
                .padding(.leading, BudgetStyle.nameX - 22)
                .accessibilityLabel("Kategorie fehlt")
        case .sub:
            Color.clear.frame(width: BudgetMetrics.cellPadding - 2)
        }
    }

    @ViewBuilder
    private var name: some View {
        if row.kind == .master {
            BudgetCategoryName(model: model, row: row, font: BudgetStyle.masterFont, isProxy: isProxy)
        } else {
            Text(verbatim: row.name)
                .font(row.kind == .uncategorized ? BudgetStyle.masterFont.font.italic() : BudgetStyle.masterFont.font)
                .foregroundStyle(ThemeColor.text)
                .lineLimit(1)
        }
    }
}

private struct BudgetRowDragIfMaster: ViewModifier {
    let model: BudgetViewModel
    let row: BudgetCategoryRow

    func body(content: Content) -> some View {
        if row.kind == .master {
            content.modifier(BudgetRowDrag(model: model, rowId: row.id))
        } else {
            content
        }
    }
}

struct BudgetCategorySubRow: View {
    let model: BudgetViewModel
    let row: BudgetCategoryRow
    let width: CGFloat
    var isProxy = false

    var body: some View {
        HStack(spacing: 2) {
            BudgetCategoryName(model: model, row: row, font: BudgetStyle.nameFont, isProxy: isProxy)
            Spacer(minLength: 0)
        }
        .padding(.leading, BudgetStyle.nameX)
        .padding(.trailing, 6)
        .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .leading)
        .background { if isProxy { Rectangle().fill(ThemeColor.contentBackground) } }
        .overlay(alignment: .bottomLeading) {
            if model.drag?.target?.lineBelow == row.id { BudgetInsertionLine(width: width - BudgetStyle.nameX + 6) }
        }
        .contentShape(Rectangle())
        .onHover { model.rowHovered(row.id, $0) }
        .budgetPopupAnchor(.categoryRow(row.id), of: model)
        .modifier(BudgetRowDrag(model: model, rowId: row.id))
    }
}

/// The system's drop indicator: an accent line that starts with a ring.
private struct BudgetInsertionLine: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(ThemeColor.accent, lineWidth: 2).frame(width: 7, height: 7)
            Rectangle().fill(ThemeColor.accent).frame(height: 2)
        }
        .frame(width: max(0, width - 6), height: 7)
        .offset(x: BudgetStyle.nameX - 6, y: 3.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
