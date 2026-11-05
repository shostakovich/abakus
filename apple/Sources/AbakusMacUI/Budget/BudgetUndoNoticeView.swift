import AbakusUI
import SwiftUI

/// What covering or filling moved, with its way back; it goes after a few seconds or with the next change.
struct BudgetUndoNoticeView: View {
    let model: BudgetViewModel
    let notice: BudgetUndoNotice

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 12) {
            Text(verbatim: notice.message)
                .foregroundStyle(ThemeColor.text)
                .lineLimit(1)
            Button(BudgetUndoNotice.undoTitle, action: model.undoNoticeClicked)
                .buttonStyle(.borderless)
                .foregroundStyle(ThemeColor.accent)
                .fontWeight(.semibold)
        }
        .font(ThemeFont.body.font)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: 32)
        .background(ThemeColor.windowBackground, in: shape)
        .overlay { shape.strokeBorder(ThemeColor.separator, lineWidth: 0.5) }
        .floatingShadow()
        .accessibilityElement(children: .contain)
        .task(id: notice.id) { await model.undoNoticeShown(notice) }
    }
}
