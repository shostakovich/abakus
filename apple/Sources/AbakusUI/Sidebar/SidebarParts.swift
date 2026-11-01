import AbakusCore
import SwiftUI

/// The sidebar draws in the dark appearance on Abakus blue, in the colours of the window's appearance.
struct SidebarColors {
    let background: Color
    let content: Color
    let muted: Color
    let accent: Color
    let negative: Color
    let badge: Color
    let badgeText: Color
    let warningBadge: Color
    let warningBadgeText: Color

    init(_ scheme: ColorScheme) {
        background = SetzkastenToken.sidebar.color(for: scheme)
        content = SetzkastenToken.sidebarContent.color(for: scheme)
        muted = SetzkastenToken.sidebarMuted.color(for: scheme)
        accent = SetzkastenToken.sidebarAccent.color(for: scheme)
        negative = SetzkastenToken.sidebarNegative.color(for: scheme)
        badge = accent
        badgeText = background
        warningBadge = SetzkastenToken.warning.color(for: scheme)
        warningBadgeText = SetzkastenToken.warningContent.color(for: scheme)
    }
}

extension EnvironmentValues {
    @Entry var sidebarColors = SidebarColors(.light)
}

/// On a selected row the system's own selection colours take over, as the accent and red would not read there.
struct SidebarIcon: View {
    let systemName: String
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.sidebarColors) private var colors

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(colors.accent))
    }
}

struct SidebarAmount: View {
    let text: String
    let amount: Decimal
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.sidebarColors) private var colors

    var body: some View {
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        if prominence == .increased { return AnyShapeStyle(.primary) }
        if amount < 0 { return AnyShapeStyle(colors.negative) }
        return AnyShapeStyle(amount == 0 ? colors.muted : colors.content)
    }
}

struct SidebarBadgeView: View {
    let badge: SidebarBadge
    @Environment(\.sidebarColors) private var colors

    var body: some View {
        Text(badge.text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(badge.isWarning ? colors.warningBadgeText : colors.badgeText)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(badge.isWarning ? colors.warningBadge : colors.badge))
            .help(badge.tooltip)
            .accessibilityLabel(Text(badge.tooltip))
    }
}

struct SidebarAccountRowView: View {
    let row: SidebarAccountRow
    let showsBalance: Bool
    @Environment(\.sidebarColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            Text(row.name).lineLimit(1).foregroundStyle(colors.content)
            if let badge = row.badge { SidebarBadgeView(badge: badge) }
            Spacer(minLength: 0)
            if showsBalance { SidebarAmount(text: row.balanceText, amount: row.balance) }
        }
        .help(row.tooltip)
    }
}

struct SidebarGroupHeader: View {
    let panel: SidebarGroupPanel
    let showsTotal: Bool
    @Environment(\.sidebarColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            Text(panel.title).lineLimit(1)
            if let badge = panel.headerBadge { SidebarBadgeView(badge: badge) }
            Spacer(minLength: 0)
            if showsTotal {
                SidebarAmount(text: panel.totalText, amount: panel.total)
                    // A section header runs to the column's edge, a row only to its selection's inset.
                    .padding(.trailing, 14)
            }
        }
        .foregroundStyle(colors.muted)
    }
}

struct SidebarFooter: View {
    let model: SidebarViewModel
    let onAddAccount: () -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.sidebarColors) private var colors

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
        .foregroundStyle(colors.muted)
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
