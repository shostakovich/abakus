import AbakusCore
import SwiftUI

struct SplitEditorView: View {
    static let deleteButtonWidth: CGFloat = 22

    let editor: TransactionEditor
    let layout: RegisterColumnLayout

    var body: some View {
        VStack(spacing: 0) {
            ForEach(editor.subIds, id: \.self) { id in
                subRow(id)
            }
            addRow
        }
        .frame(width: layout.displayWidth, alignment: .topLeading)
    }

    private func subRow(_ id: String) -> some View {
        ZStack(alignment: .topLeading) {
            if let payee = layout.frame(of: .payee) {
                Button {
                    editor.deleteSubRow(id)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: RegisterGridStyle.symbolSize))
                        .foregroundStyle(ThemeColor.secondaryText)
                        .frame(width: Self.deleteButtonWidth, height: EditRowMetrics.subRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Teil entfernen")
                .offset(x: max(0, payee.x - Self.deleteButtonWidth))
            }
            ForEach(Self.fieldFrames(layout.frames, editor: editor), id: \.column) { column, frame in
                EditTextCell(
                    editor: editor, field: .sub(id, column), width: frame.width, height: EditRowMetrics.subRowHeight,
                    accessory: column == .payee || column == .category ? .suggestions : nil
                )
                .offset(x: frame.x)
            }
            if let frame = layout.frame(of: .errorState), let symbol = subErrorSymbol(id) {
                StatusSymbolImage(symbol: symbol)
                    .frame(width: frame.width, height: EditRowMetrics.subRowHeight)
                    .offset(x: frame.x)
            }
        }
        .frame(width: layout.displayWidth, height: EditRowMetrics.subRowHeight, alignment: .topLeading)
    }

    static func fieldFrames(_ frames: [RegisterColumnFrame], editor: TransactionEditor)
        -> [(column: EditorColumn, frame: RegisterColumnFrame)]
    {
        let columns = editor.subColumns()
        return frames.compactMap { frame in
            EditorColumn(frame.column).flatMap { columns.contains($0) ? ($0, frame) : nil }
        }
    }

    private func subErrorSymbol(_ id: String) -> StatusSymbol? {
        guard let sub = editor.original.subtransactions.first(where: { $0.id == id }) else { return nil }
        return editor.store.budget.errorState(of: sub, inAccount: editor.original.accountId).level.symbol
    }

    private var addRow: some View {
        let remaining = editor.remainingTexts
        let inset = RegisterGridStyle.cellInset
        return ZStack(alignment: .leading) {
            Button("Teil hinzufügen", systemImage: "plus", action: editor.addSubRow)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
                .offset(x: (layout.frame(of: .payee)?.x ?? 0) + EditCellStyle.fieldInset)
            if let outflow = layout.frame(of: .outflow), let inflow = layout.frame(of: .inflow) {
                Text("Noch aufzuteilen:")
                    .foregroundStyle(ThemeColor.secondaryText)
                    .lineLimit(1)
                    .frame(width: max(0, outflow.x - inset), alignment: .trailing)
                remainingLabel(remaining.outflow, in: outflow)
                remainingLabel(remaining.inflow, in: inflow)
            }
        }
        .font(EditCellStyle.font.font)
        .frame(width: layout.displayWidth, height: EditRowMetrics.splitAddRowHeight, alignment: .leading)
    }

    private func remainingLabel(_ text: String, in frame: RegisterColumnFrame) -> some View {
        Text(verbatim: text)
            .font(ThemeFont.tableEmphasized.font)
            .lineLimit(1)
            .padding(.trailing, EditCellStyle.fieldInset + EditCellStyle.textInset)
            .frame(width: frame.width, alignment: .trailing)
            .offset(x: frame.x)
    }
}
