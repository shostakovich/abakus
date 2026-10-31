import SwiftUI

/// One line of grid text the system truncates; the tooltip shows what the truncation hides.
struct GridCellLabel: View {
    enum Tip {
        case none
        case whenTruncated
        case always(String?)
    }

    let text: String
    let font: ThemeFont
    let color: Color
    let width: CGFloat
    var leadingInset = RegisterGridStyle.cellInset
    var alignment = Alignment.leading
    var truncation = Text.TruncationMode.tail
    var tip = Tip.none

    var body: some View {
        Text(verbatim: text)
            .font(font.font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(truncation)
            .padding(.leading, leadingInset)
            .padding(.trailing, RegisterGridStyle.cellInset)
            .frame(width: max(0, width), height: RegisterMetrics.rowHeight, alignment: alignment)
            .toolTip(toolTip)
    }

    private var toolTip: String? {
        switch tip {
        case .none: nil
        case .whenTruncated:
            Self.isTruncated(text, font: font, room: width - leadingInset - RegisterGridStyle.cellInset) ? text : nil
        case .always(let text): text
        }
    }

    static func isTruncated(_ text: String, font: ThemeFont, room: CGFloat) -> Bool {
        font.width(of: text) > room
    }
}
