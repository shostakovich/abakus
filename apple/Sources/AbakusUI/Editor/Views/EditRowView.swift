import AbakusCore
import AppKit
import SwiftUI

enum EditCellStyle {
    static let font = ThemeFont.table
    static let fieldCornerRadius: CGFloat = 5
    static let fieldInset: CGFloat = 2
    static let textInset: CGFloat = 6
    static let accessoryWidth: CGFloat = 18
    /// The calculator and the sign button at an amount field's start.
    static let amountAccessoriesWidth: CGFloat = 2 * accessoryWidth
}

struct EditorAnchorKey: PreferenceKey {
    static let defaultValue: [EditorFieldID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [EditorFieldID: Anchor<CGRect>], nextValue: () -> [EditorFieldID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct EditRowView: View {
    let editor: TransactionEditor
    let layout: RegisterColumnLayout
    let row: RegisterRow?
    let main: RegisterViewModel?

    var body: some View {
        VStack(spacing: 0) {
            fieldBand
                .padding(.top, EditRowMetrics.padding)
            if editor.isSplitMode {
                SplitEditorView(editor: editor, layout: layout)
            }
            EditButtonRow(editor: editor, width: layout.displayWidth)
        }
        .frame(width: layout.displayWidth, height: editor.rowHeight, alignment: .topLeading)
        .background(ThemeColor.selection)
        .clipped()
    }

    private var fieldBand: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.frames, id: \.column) { frame in
                cell(frame)
                    .frame(width: frame.width, height: EditRowMetrics.fieldBandHeight)
                    .offset(x: frame.x)
            }
        }
        .frame(width: layout.displayWidth, height: EditRowMetrics.fieldBandHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func cell(_ frame: RegisterColumnFrame) -> some View {
        switch frame.column {
        case .account:
            EditTextCell(editor: editor, field: .main(.account), width: frame.width, accessory: .suggestions)
        case .date:
            EditTextCell(editor: editor, field: .main(.date), width: frame.width, accessory: .calendar)
        case .frequency:
            FrequencyEditCell(editor: editor, width: frame.width)
        case .payee:
            EditTextCell(
                editor: editor, field: .main(.payee), width: frame.width, accessory: .suggestions,
                transferLink: editor.mode == .existing && editor.budget.isTransfer(editor.original)
                    && !editor.isScheduled
                    ? { if let row { main?.transferIconClicked(row) } } : nil)
        case .category:
            EditTextCell(editor: editor, field: .main(.category), width: frame.width, accessory: .suggestions)
        case .memo:
            EditTextCell(editor: editor, field: .main(.memo), width: frame.width)
        case .amount:
            EditTextCell(editor: editor, field: .main(.amount), width: frame.width)
        case .runningBalance:
            if let row {
                Text(verbatim: row.runningBalance)
                    .font(EditCellStyle.font.font)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .lineLimit(1)
                    .padding(.trailing, RegisterGridStyle.cellInset)
                    .frame(width: frame.width, alignment: .trailing)
            }
        case .cleared:
            let cleared = editor.clone.cleared
            EditRowSymbolButton(
                symbol: cleared.symbol, width: frame.width,
                pointer: cleared != .reconciled
            ) {
                if let row, let main { main.clearedClicked(row) } else { editor.toggleCleared() }
            }
            .toolTip(RegisterRow.clearedTooltip(cleared))
        }
    }
}

struct EditRowSymbolButton: View {
    let symbol: StatusSymbol
    let width: CGFloat
    var pointer = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StatusSymbolImage(symbol: symbol)
                .frame(width: width, height: EditRowMetrics.fieldBandHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerStyle(pointer ? .link : nil)
    }
}

struct EditTextCell: View {
    enum Accessory {
        case suggestions
        case calendar
    }

    let editor: TransactionEditor
    let field: EditorFieldID
    let width: CGFloat
    var height: CGFloat = EditRowMetrics.fieldBandHeight
    var accessory: Accessory?
    var transferLink: (() -> Void)?

    var body: some View {
        if editor.isLocked(field) { locked } else { editable }
    }

    private var editable: some View {
        let isFocused = editor.focus == .field(field)
        let shape = RoundedRectangle(cornerRadius: EditCellStyle.fieldCornerRadius)
        return HStack(spacing: 0) {
            transferButton
            if field.column.isAmount {
                calculatorButton
                signButton
            }
            text(isFocused: isFocused)
            trailingAccessory
        }
        .padding(.leading, transferLink == nil && !field.column.isAmount ? EditCellStyle.textInset - 2 : 0)
        .padding(.trailing, accessory == nil ? EditCellStyle.textInset - 2 : 0)
        .frame(width: max(0, width - 2 * EditCellStyle.fieldInset), height: EditRowMetrics.fieldHeight)
        .background(isFocused ? AnyShapeStyle(ThemeColor.fieldBackground) : AnyShapeStyle(.clear), in: shape)
        .overlay {
            shape.strokeBorder(
                isFocused ? AnyShapeStyle(ThemeColor.accent) : AnyShapeStyle(ThemeColor.fieldOutline), lineWidth: 1)
        }
        .focusRing(isFocused, cornerRadius: EditCellStyle.fieldCornerRadius)
        .contentShape(shape)
        .onTapGesture { if !isFocused { editor.fieldClicked(field) } }
        .anchorPreference(key: EditorAnchorKey.self, value: .bounds) { [field: $0] }
        .frame(width: width, height: height)
    }

    /// Plain text like a disabled field, so the row shows at a glance what stays.
    private var locked: some View {
        let text = editor.text(field)
        let sign = field.column.isAmount && !text.isEmpty ? (editor.isInflow(field) ? "+" : "−") : ""
        return HStack(spacing: 0) {
            transferButton
            Text(verbatim: sign + text)
                .font(EditCellStyle.font.font)
                .foregroundStyle(ThemeColor.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: field.column.isAmount ? .trailing : .leading)
        }
        .padding(.leading, transferLink == nil ? EditCellStyle.textInset - 2 : 0)
        .padding(.trailing, EditCellStyle.textInset - 2)
        .frame(width: max(0, width - 2 * EditCellStyle.fieldInset), height: EditRowMetrics.fieldHeight)
        .contentShape(Rectangle())
        .toolTip(editor.lockReason)
        .anchorPreference(key: EditorAnchorKey.self, value: .bounds) { [field: $0] }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var transferButton: some View {
        if let transferLink {
            let symbol = StatusSymbol.transfer
            accessoryButton(symbol.name, label: symbol.label, action: transferLink)
                .toolTip("Zur Gegenbuchung springen")
        }
    }

    private var signButton: some View {
        let isInflow = editor.isInflow(field)
        return Button {
            editor.toggleSign(field)
        } label: {
            Text(verbatim: isInflow ? "+" : "−")
                .font(ThemeFont.tableEmphasized.font)
                .foregroundStyle(isInflow ? ThemeColor.positive : ThemeColor.secondaryText)
                .frame(width: EditCellStyle.accessoryWidth, height: EditRowMetrics.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerStyle(.link)
        .toolTip("Zwischen Ausgang und Eingang wechseln (+ oder − tippen)")
        .accessibilityLabel(isInflow ? "Eingang" : "Ausgang")
        .accessibilityHint("Vorzeichen wechseln")
    }

    private var calculatorButton: some View {
        Button {
            editor.openCalculator(for: field)
        } label: {
            CalculatorGlyph()
                .foregroundStyle(ThemeColor.secondaryText)
                .frame(width: EditCellStyle.accessoryWidth, height: EditRowMetrics.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerStyle(.link)
        .toolTip("Rechner")
        .accessibilityLabel("Rechner")
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch accessory {
        case .suggestions:
            accessoryButton("chevron.down", label: "Liste zeigen") { editor.dropDownArrowClicked(field) }
        case .calendar:
            accessoryButton(
                "calendar", label: "Datum wählen", tint: editor.isCalendarOpen ? ThemeColor.accent : nil,
                action: editor.toggleCalendar)
        case nil:
            EmptyView()
        }
    }

    private func accessoryButton(
        _ systemImage: String, label: String, tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? ThemeColor.secondaryText)
                .frame(width: EditCellStyle.accessoryWidth, height: EditRowMetrics.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerStyle(.link)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func text(isFocused: Bool) -> some View {
        let isAmount = field.column.isAmount
        if isFocused {
            EditorTextField(
                editor: editor, field: field, font: EditCellStyle.font, prompt: editor.prompt(field),
                alignment: isAmount ? .right : .left, isActive: !editor.hasOpenDialog
            )
            .frame(maxWidth: .infinity)
            .frame(height: EditorFieldMetrics.height(EditCellStyle.font))
        } else {
            let text = editor.text(field)
            // The AppKit field draws its text 2 pt inside its frame.
            Text(verbatim: text.isEmpty ? editor.prompt(field) : text)
                .font(EditCellStyle.font.font)
                .foregroundStyle(text.isEmpty ? AnyShapeStyle(ThemeColor.tertiaryText) : AnyShapeStyle(ThemeColor.text))
                .lineLimit(1)
                .truncationMode(field.column == .category ? .middle : .tail)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: isAmount ? .trailing : .leading)
        }
    }
}

struct FrequencyEditCell: View {
    let editor: TransactionEditor
    let width: CGFloat

    var body: some View {
        let field = EditorFieldID.main(.frequency)
        let isFocused = editor.focus == .field(field)
        let shape = RoundedRectangle(cornerRadius: EditCellStyle.fieldCornerRadius)
        HStack(spacing: 2) {
            Text(verbatim: editor.frequency?.readableName ?? "")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ThemeColor.secondaryText)
        }
        .font(EditCellStyle.font.font)
        .padding(.horizontal, EditCellStyle.textInset)
        .frame(width: max(0, width - 2 * EditCellStyle.fieldInset), height: EditRowMetrics.fieldHeight)
        .background(ThemeColor.fieldBackground, in: shape)
        .overlay { shape.strokeBorder(ThemeColor.fieldOutline, lineWidth: 1) }
        .focusRing(isFocused && !editor.isFrequencyListOpen, cornerRadius: EditCellStyle.fieldCornerRadius)
        .contentShape(shape)
        .onTapGesture { editor.frequencyClicked() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .anchorPreference(key: EditorAnchorKey.self, value: .bounds) { [field: $0] }
        .frame(width: width, height: EditRowMetrics.fieldBandHeight)
    }
}

@MainActor
enum EditorFieldMetrics {
    private static var heights: [ThemeFont: CGFloat] = [:]

    static func height(_ font: ThemeFont) -> CGFloat {
        if let cached = heights[font] { return cached }
        let probe = NSTextField(string: "Xg")
        probe.isBordered = false
        probe.isBezeled = false
        probe.font = font.nsFont
        probe.sizeToFit()
        let height = ceil(probe.fittingSize.height)
        heights[font] = height
        return height
    }
}

/// SF Symbols has no calculator, so it is drawn: a case, a display, round keys and a tall one.
struct CalculatorGlyph: View {
    var body: some View {
        Canvas { context, size in
            let body = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(Path(roundedRect: body, cornerRadius: 2), with: .foreground, lineWidth: 1)
            context.fill(Path(CGRect(x: 2.5, y: 2.5, width: size.width - 5, height: 2)), with: .foreground)
            let key: CGFloat = 1.6
            let pitch = (size.width - 5 - key) / 2
            for row in 0..<3 {
                for column in 0..<3 where !(column == 2 && row > 0) {
                    let origin = CGPoint(x: 2.5 + CGFloat(column) * pitch, y: 6 + CGFloat(row) * 2.5)
                    context.fill(
                        Path(ellipseIn: CGRect(origin: origin, size: CGSize(width: key, height: key))),
                        with: .foreground)
                }
            }
            let tall = CGRect(x: 2.5 + 2 * pitch, y: 8.5, width: key, height: 2.5 + key)
            context.fill(Path(roundedRect: tall, cornerRadius: key / 2), with: .foreground)
        }
        .frame(width: 11, height: 14)
    }
}
