import SwiftUI

@MainActor
package enum SchedulerMetrics {
    package static let dividerThickness: CGFloat = 1
    package static let dividerHitHeight: CGFloat = 9
    package static let titleHeight: CGFloat = 36
    static let mainPanelMinimumHeight: CGFloat = 250
    package static let titleFont = ThemeFont(size: 15, weight: .semibold)
    package static var animation: Animation? { .motion(RegisterEffects.schedulerSlide) }

    /// The divider keeps the main panel at its 250 pt minimum and the scheduled section at 185 or more.
    package static func height(saved: CGFloat, available: CGFloat) -> CGFloat {
        let maximum = available - dividerThickness - mainPanelMinimumHeight
        return max(RegisterScheduler.minimumHeight, min(saved, maximum))
    }
}
