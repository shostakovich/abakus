import AbakusCore
import SwiftUI

extension BudgetTargetState {
    package var symbol: StatusSymbol? {
        switch self {
        case .overspent: nil
        case .snoozed: StatusSymbol(name: "pause.circle.fill", color: ThemeColor.secondaryText, label: "Pausiert")
        case .underfunded: BudgetAvailableMarker.underfunded.symbol
        case .onTrack, .met: BudgetAvailableMarker.funded.symbol
        }
    }

    package var textColor: Color {
        switch self {
        case .overspent: ThemeColor.negative
        case .snoozed: ThemeColor.secondaryText
        case .underfunded: ThemeColor.warning
        case .onTrack, .met: ThemeColor.positive
        }
    }
}

extension BudgetAvailableMarker {
    package var symbol: StatusSymbol {
        switch self {
        case .underfunded: StatusSymbol(name: "clock.fill", color: ThemeColor.warning, label: label)
        case .funded: StatusSymbol(name: "checkmark.circle.fill", color: ThemeColor.positive, label: label)
        case .snoozed: StatusSymbol(name: "pause.circle.fill", color: ThemeColor.secondaryText, label: label)
        }
    }
}

/// How much of an underfunded target's month is funded: a track and an arc clockwise from 12 o'clock.
package struct BudgetTargetRing: View {
    let percent: Int
    let color: Color

    package init(percent: Int, color: Color) {
        self.percent = percent
        self.color = color
    }

    package var body: some View {
        let width = BudgetStyle.ringLineWidth
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
        .frame(width: BudgetStyle.ringSize, height: BudgetStyle.ringSize)
    }
}
