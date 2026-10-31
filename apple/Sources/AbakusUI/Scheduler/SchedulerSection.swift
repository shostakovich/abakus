import AbakusCore
import SwiftUI

@MainActor
enum SchedulerMetrics {
    static let dividerThickness: CGFloat = 1
    static let dividerHitHeight: CGFloat = 9
    static let titleHeight: CGFloat = 36
    static let mainPanelMinimumHeight: CGFloat = 250
    static let titleFont = ThemeFont(size: 15, weight: .semibold)
    /// The frequency pop-up's outline and its ↕ beside the text.
    static let popUpAccessory: CGFloat = 2 * EditCellStyle.fieldInset + 12
    static var animation: Animation? { .motion(RegisterEffects.schedulerSlide) }

    /// The divider keeps the main panel at its 250 pt minimum and the scheduled section at 185 or more.
    static func height(saved: CGFloat, available: CGFloat) -> CGFloat {
        let maximum = available - dividerThickness - mainPanelMinimumHeight
        return max(RegisterScheduler.minimumHeight, min(saved, maximum))
    }
}

/// The collapsible Scheduled Transactions section: its title with the + menu over the schedule grid.
struct SchedulerSection: View {
    let model: RegisterViewModel
    let size: CGSize

    var body: some View {
        let gridHeight = max(RegisterMetrics.headerHeight, size.height - SchedulerMetrics.titleHeight)
        VStack(spacing: 0) {
            SchedulerTitleBar(model: model)
                .frame(height: SchedulerMetrics.titleHeight)
            RegisterGridView(owner: model.scheduler, size: CGSize(width: size.width, height: gridHeight))
                .id(model.accountKey)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}

private struct SchedulerTitleBar: View {
    let model: RegisterViewModel

    var body: some View {
        HStack(spacing: 8) {
            collapseButton
            Spacer(minLength: 8)
            addMenu
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
        .background(ThemeColor.windowBackground)
    }

    private var collapseButton: some View {
        Button(action: model.scheduledToggleClicked) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThemeColor.secondaryText)
                    .accessibilityHidden(true)
                Text(verbatim: RegisterScheduler.title)
                    .font(SchedulerMetrics.titleFont.font)
                    .accessibilityAddTraits(.isHeader)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.scheduledToggleTooltip)
        .registerAnchor(.schedulerTitle)
    }

    private var addMenu: some View {
        let scheduler = model.scheduler
        return Menu {
            Button(RegisterScheduler.addTitle, action: scheduler.addClicked)
            if scheduler.showsTransferButton {
                Button(RegisterScheduler.transferTitle, action: scheduler.transferClicked)
            }
        } label: {
            Label(RegisterToolbar.addMenuTitle, systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(!scheduler.canAddTransactions)
    }
}

/// A native hairline between the register and the scheduled section, dragged live; its saved height stays.
struct SchedulerDivider: View {
    let currentHeight: CGFloat
    let available: CGFloat
    let onResize: (CGFloat) -> Void
    @State private var startHeight: CGFloat?

    var body: some View {
        Divider()
            .frame(height: SchedulerMetrics.dividerThickness)
            .overlay {
                Color.clear
                    .frame(height: SchedulerMetrics.dividerHitHeight)
                    .contentShape(Rectangle())
                    .pointerStyle(.rowResize)
                    .gesture(drag)
            }
            .zIndex(1)
            .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = startHeight ?? currentHeight
                if startHeight == nil { startHeight = currentHeight }
                onResize(SchedulerMetrics.height(saved: start - value.translation.height, available: available))
            }
            .onEnded { _ in startHeight = nil }
    }
}
