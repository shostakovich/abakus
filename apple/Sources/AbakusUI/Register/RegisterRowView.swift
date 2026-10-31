import AbakusCore
import AppKit
import SwiftUI

struct RegisterRowView: View {
    static let balanceHoverDelay = Duration.milliseconds(650)

    let row: RegisterRow
    let layout: RegisterColumnLayout
    let isSelected: Bool
    let owner: any RegisterGridOwner
    let onClick: () -> Void
    @State private var balanceHover: Task<Void, Never>?
    @State private var glow: Double = 0
    @State private var isGlowing = false

    private var main: RegisterViewModel? { owner.mainGrid }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            cells
                .strikethrough(row.isExcludedFromSearch, color: ThemeColor.secondaryText)
        }
        .frame(
            minWidth: layout.displayWidth, maxWidth: layout.gridWidth, minHeight: RegisterMetrics.rowHeight,
            maxHeight: RegisterMetrics.rowHeight, alignment: .topLeading
        )
        .clipped()
        .overlay {
            if isGlowing { addedGlow }
        }
        .zIndex(isGlowing ? 1 : 0)
        .task(id: glowStart) { await playAddedGlow() }
        .anchorPreference(key: IncomeCheckAnchorKey.self, value: .bounds) { anchor in
            guard !row.isSubtransaction, main?.incomeCheck?.transactionId == row.transactionId,
                let outflow = layout.frame(of: .outflow)
            else { return nil }
            return IncomeCheckAnchor(row: anchor, outflow: outflow)
        }
        .anchorPreference(key: AdjustmentHelpAnchorKey.self, value: .bounds) { anchor in
            isAdjustmentHelpRow ? anchor : nil
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                let column = layout.column(atX: value.location.x)
                if owner.grid.rowClicked(row.transactionId, column: column, modifiers: .current) { onClick() }
            })
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            ThemeColor.accent
        } else if isAdjustmentHelpRow {
            RegisterGridStyle.adjustmentRow
        } else if isGlowing {
            RegisterGridStyle.addedRowCanvas
        } else {
            Color.clear
        }
    }

    private var glowStart: ContinuousClock.Instant? {
        row.isSubtransaction ? nil : main?.addedRowGlowStart(row.transactionId)
    }

    /// The glow sits on a canvas below the row; multiplying keeps the neighbours' text dark where it spreads.
    private var addedGlow: some View {
        Rectangle().fill(.white)
            .padding(2)
            .glow(RegisterGridStyle.addedRowGlow, intensity: glow)
            .compositingGroup()
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }

    /// A row the lazy list rebuilds mid-glow picks up where the sequence is.
    private func playAddedGlow() async {
        let phase = RegisterEffects.glowPhase.duration
        guard let start = glowStart else { return }
        let elapsed = start.duration(to: .now)
        guard elapsed < phase * 2 else { return }
        isGlowing = true
        if elapsed < phase {
            withAnimation(.motion(RegisterEffects.glowPhase, duration: phase - elapsed)) { glow = 1 }
            try? await Task.sleep(for: phase - elapsed)
            guard !Task.isCancelled else { return }
        } else {
            glow = 1 - RegisterEffects.glowPhase.curve.value(at: (elapsed - phase) / phase)
        }
        let remaining = phase * 2 - max(elapsed, phase)
        withAnimation(.motion(RegisterEffects.glowPhase, duration: remaining)) { glow = 0 }
        try? await Task.sleep(for: remaining)
        guard !Task.isCancelled else { return }
        isGlowing = false
    }

    private var isAdjustmentHelpRow: Bool {
        !row.isSubtransaction && main?.adjustmentHelp?.transactionId == row.transactionId
    }

    private var cells: some View {
        let isPopupRow = main?.popup?.rowId == row.id
        return ZStack(alignment: .topLeading) {
            ForEach(layout.frames, id: \.column) { frame in
                Group {
                    if row.isSubtransaction { subCell(frame) } else { cell(frame) }
                }
                .frame(width: frame.width, height: RegisterMetrics.rowHeight, alignment: .topLeading)
                .clipped()
                .anchorPreference(key: RegisterAnchorKey.self, value: .bounds) { anchor in
                    guard isPopupRow, let id = Self.anchorID(frame.column, row: row) else { return [:] }
                    return [id: anchor]
                }
                .offset(x: frame.x)
            }
        }
    }

    /// A split line anchors only its error popup.
    static func anchorID(_ column: RegisterColumn, row: RegisterRow) -> RegisterAnchorID? {
        switch column {
        case .errorState: .error(row.id)
        case .runningBalance where !row.isSubtransaction: .balance(row.id)
        default: nil
        }
    }

    @ViewBuilder
    private func cell(_ frame: RegisterColumnFrame) -> some View {
        switch frame.column {
        case .account: text(row.account, width: frame.width)
        case .date: text(row.date, width: frame.width)
        case .frequency: text(row.frequency, width: frame.width)
        case .payee: payee(width: frame.width)
        case .errorState: errorCell(width: frame.width)
        case .category: category(width: frame.width)
        case .memo: text(row.memo, width: frame.width, tip: .whenTruncated)
        case .outflow: amount(row.outflow, width: frame.width)
        case .inflow: amount(row.inflow, width: frame.width)
        case .runningBalance:
            amount(row.runningBalance, width: frame.width)
                .contentShape(Rectangle())
                .onHover(perform: balanceHovered)
        case .cleared: clearedCell(width: frame.width)
        }
    }

    /// Payee onwards, indented; the columns left of Payee stay empty.
    @ViewBuilder
    private func subCell(_ frame: RegisterColumnFrame) -> some View {
        let indent = RegisterGridStyle.cellInset + RegisterGridStyle.subRowIndent
        switch frame.column {
        case .payee: payee(width: frame.width, leadingInset: indent)
        case .errorState: errorCell(width: frame.width)
        case .category: category(width: frame.width, leadingInset: indent)
        case .memo: text(row.memo, width: frame.width, tip: .whenTruncated)
        case .outflow: amount(row.outflow, width: frame.width)
        case .inflow: amount(row.inflow, width: frame.width)
        default: EmptyView()
        }
    }

    private var textFont: ThemeFont {
        row.textStyle == .bold ? RegisterGridStyle.rowBoldFont : RegisterGridStyle.rowFont
    }

    private var textColor: Color {
        if isSelected { return ThemeColor.selectedText }
        return row.isExcludedFromSearch ? ThemeColor.secondaryText : ThemeColor.text
    }

    private func tint() -> Color? {
        isSelected ? ThemeColor.selectedText : nil
    }

    private func balanceHovered(_ inside: Bool) {
        balanceHover?.cancel()
        guard inside else {
            main?.runningBalanceHovered(row, inside: false)
            return
        }
        balanceHover = Task { @MainActor in
            try? await Task.sleep(for: Self.balanceHoverDelay)
            guard !Task.isCancelled else { return }
            main?.runningBalanceHovered(row, inside: true)
        }
    }

    private func text(_ value: String, width: CGFloat, tip: GridCellLabel.Tip = .none) -> some View {
        GridCellLabel(text: value, font: textFont, color: textColor, width: width, tip: tip)
    }

    private func amount(_ value: String, width: CGFloat) -> some View {
        GridCellLabel(text: value, font: textFont, color: textColor, width: width, alignment: .trailing)
    }

    private func payee(width: CGFloat, leadingInset: CGFloat = RegisterGridStyle.cellInset) -> some View {
        HStack(spacing: 0) {
            GridCellLabel(
                text: row.payee, font: textFont, color: textColor,
                width: width - (row.hasTransferIcon ? Self.symbolButtonWidth : 0), leadingInset: leadingInset,
                tip: .always(row.payeeTooltip))
            if row.hasTransferIcon {
                transferButton
            }
        }
        .frame(width: width, alignment: .leading)
    }

    static let symbolButtonWidth: CGFloat = 22
    static let chevronWidth: CGFloat = 16

    @ViewBuilder
    private var transferButton: some View {
        let image = StatusSymbolImage(symbol: .transfer, tint: tint())
            .frame(width: Self.symbolButtonWidth, height: RegisterMetrics.rowHeight)
        if let main {
            symbolButton(image) { main.transferIconClicked(row) }
                .toolTip("Zur Gegenbuchung springen")
        } else {
            image
        }
    }

    @ViewBuilder
    private func errorCell(width: CGFloat) -> some View {
        if let symbol = row.errorLevel.symbol {
            symbolButton(
                StatusSymbolImage(symbol: symbol, tint: tint())
                    .frame(width: width, height: RegisterMetrics.rowHeight)
            ) {
                main?.errorIconClicked(row)
            }
            .toolTip(row.errorMessage)
        }
    }

    private func clearedCell(width: CGFloat) -> some View {
        let symbol = row.cleared.symbol(reconciling: main?.isReconciling ?? false)
        return symbolButton(
            StatusSymbolImage(symbol: symbol, tint: tint()).frame(width: width, height: RegisterMetrics.rowHeight),
            pointer: row.cleared != .reconciled
        ) {
            main?.clearedClicked(row)
        }
        .toolTip(row.clearedTooltip)
    }

    private func symbolButton<Label: View>(_ label: Label, pointer: Bool = true, action: @escaping () -> Void)
        -> some View
    {
        Button {
            action()
            if !owner.grid.hasOpenEdit { onClick() }
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(pointer ? .link : nil)
    }

    private func category(width: CGFloat, leadingInset: CGFloat = RegisterGridStyle.cellInset) -> some View {
        let hasChevron = row.split != .none
        let font: ThemeFont
        let color: Color
        switch row.categoryStyle {
        case .plain: (font, color) = (RegisterGridStyle.rowFont, textColor)
        case .bold: (font, color) = (RegisterGridStyle.rowBoldFont, textColor)
        case .needsCategory: (font, color) = (RegisterGridStyle.rowFont, isSelected ? textColor : ThemeColor.warning)
        case .error: (font, color) = (RegisterGridStyle.rowFont, isSelected ? textColor : ThemeColor.negative)
        }
        let chevronX = leadingInset - 2
        return HStack(spacing: 0) {
            if hasChevron {
                symbolButton(
                    Image(systemName: row.split == .expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? ThemeColor.selectedText : ThemeColor.secondaryText)
                        .frame(width: Self.chevronWidth, height: RegisterMetrics.rowHeight)
                ) {
                    owner.grid.toggleSplit(row.transactionId)
                }
                .padding(.leading, chevronX)
                .accessibilityLabel(row.split == .expanded ? "Teile einklappen" : "Teile ausklappen")
            }
            GridCellLabel(
                text: row.category, font: font, color: color,
                width: hasChevron ? width - chevronX - Self.chevronWidth : width,
                leadingInset: hasChevron ? 0 : leadingInset, truncation: .middle, tip: .whenTruncated)
        }
        .frame(width: width, alignment: .leading)
    }
}

extension RegisterClickModifiers {
    /// Command and Control count alike.
    @MainActor static var current: RegisterClickModifiers {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        var modifiers: RegisterClickModifiers = []
        if flags.contains(.command) || flags.contains(.control) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
