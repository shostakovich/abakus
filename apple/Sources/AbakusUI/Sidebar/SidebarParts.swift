import AbakusCore
import SwiftUI

/// On a selected row the system's own selection colours take over, as the accent and red would not read there.
struct SidebarIcon: View {
    let systemName: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(ThemeColor.accent))
    }
}

struct SidebarAmount: View {
    let text: String
    let isNegative: Bool
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        if prominence == .increased { return AnyShapeStyle(.primary) }
        return isNegative ? AnyShapeStyle(ThemeColor.negative) : AnyShapeStyle(ThemeColor.secondaryText)
    }
}

struct SidebarBadgeView: View {
    let badge: SidebarBadge

    var body: some View {
        Text(badge.text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(badge.isWarning ? ThemeColor.warning : Color.secondary))
            .help(badge.tooltip)
            .accessibilityLabel(Text(badge.tooltip))
    }
}

struct SidebarAccountRowView: View {
    let row: SidebarAccountRow
    let showsBalance: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(row.name).lineLimit(1)
            if let badge = row.badge { SidebarBadgeView(badge: badge) }
            Spacer(minLength: 0)
            if showsBalance { SidebarAmount(text: row.balanceText, isNegative: row.isNegative) }
        }
        .help(row.tooltip)
    }
}

struct SidebarGroupHeader: View {
    let panel: SidebarGroupPanel
    let showsTotal: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(panel.title).lineLimit(1)
            if let badge = panel.headerBadge { SidebarBadgeView(badge: badge) }
            Spacer(minLength: 0)
            if showsTotal { SidebarAmount(text: panel.totalText, isNegative: panel.isNegative) }
        }
    }
}

struct SidebarFooter: View {
    let model: SidebarViewModel
    let onAddAccount: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAddAccount) {
                Label(model.addAccountTitle, systemImage: "plus")
                    .lineLimit(1)
                    .frame(minHeight: 20)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            Button {
                openSettings()
            } label: {
                Image(systemName: model.cloudStatus.symbolName)
                    .frame(minWidth: 20, minHeight: 20)
                    .contentShape(Rectangle())
            }
            .help(model.cloudStatus.tooltip)
            .accessibilityLabel("Synchronisation")
            footerIcon(
                model.isFullView
                    ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.line.vertical.and.arrow.right",
                label: model.toggleCommandTitle, action: model.toggleSidebar
            )
            .help(model.toggleTooltip)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(ThemeColor.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footerIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(minWidth: 20, minHeight: 20)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
