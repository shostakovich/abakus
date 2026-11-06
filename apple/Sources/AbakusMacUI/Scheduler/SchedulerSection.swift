import AbakusCore
import AbakusUI
import SwiftUI

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
                .overlay {
                    if model.scheduler.scheduledIds.isEmpty {
                        VStack(spacing: 4) {
                            Text(RegisterScheduler.emptyTitle).font(ThemeFont.headline.font)
                            Text(RegisterScheduler.emptyMessage).foregroundStyle(ThemeColor.secondaryText)
                        }
                        .allowsHitTesting(false)
                    }
                }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}

struct SchedulerTitleBar: View {
    let model: RegisterViewModel

    var body: some View {
        HStack(spacing: 8) {
            collapseButton
            Spacer(minLength: 8)
            addButton
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
        .background(ThemeColor.windowBackground)
    }

    private var collapseButton: some View {
        Button(action: model.scheduledToggleClicked) {
            HStack(spacing: 6) {
                Image(systemName: model.isSchedulerVisible ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThemeColor.secondaryText)
                    .accessibilityHidden(true)
                Text(verbatim: model.scheduledSummary ?? RegisterScheduler.title)
                    .font(SchedulerMetrics.titleFont.font)
                    .accessibilityAddTraits(.isHeader)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.scheduledToggleTooltip)
    }

    private var addButton: some View {
        let scheduler = model.scheduler
        return Button(action: scheduler.addClicked) {
            Label(RegisterScheduler.addTitle, systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .fixedSize()
        .disabled(!scheduler.canAddTransactions)
        .help(RegisterScheduler.addTitle)
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
