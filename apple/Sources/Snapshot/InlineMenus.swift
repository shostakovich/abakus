import AbakusCore
import AbakusMacUI
import AbakusUI
import AppKit
import SwiftUI

/// Records the menus the app would pop and draws them over the window: a native menu offscreen waits for a click.
@MainActor
@Observable
final class SnapshotMenus {
    struct Shown {
        var items: [RegisterMenuItem]
        /// The menu's top-left corner below the toolbar, top-left origin.
        var location: CGPoint
    }

    private(set) var shown: Shown?

    func reset() {
        shown = nil
    }

    var presenter: MenuPresenter {
        MenuPresenter { [weak self] items, point, view, _ in
            guard let content = view.window?.contentView else { return }
            let location = content.convert(point, from: view)
            self?.shown = Shown(
                items: items,
                location: CGPoint(
                    x: location.x,
                    y: (content.isFlipped ? location.y : content.bounds.height - location.y)
                        - content.safeAreaInsets.top)
            )
        }
    }
}

struct SnapshotWindowContent: View {
    let model: AppModel
    let menus: SnapshotMenus?

    var body: some View {
        if let menus {
            MainWindowContent(model: model)
                .environment(\.menuPresenter, menus.presenter)
                .overlay(alignment: .topLeading) { InlineMenuLayer(menus: menus) }
        } else {
            MainWindowContent(model: model)
        }
    }
}

private struct InlineMenuLayer: View {
    let menus: SnapshotMenus

    var body: some View {
        GeometryReader { proxy in
            if let menu = menus.shown {
                let metrics = InlineMenuMetrics(menu.items)
                let size = metrics.size
                let point = menu.location
                // A toolbar button's menu starts above the content, under the toolbar the content cannot draw over.
                InlineMenuView(items: menu.items, metrics: metrics)
                    .offset(
                        x: min(point.x, proxy.size.width - size.width - 4),
                        y: point.y + size.height > proxy.size.height ? max(0, point.y - size.height) : max(0, point.y))
            }
        }
        .allowsHitTesting(false)
    }
}

/// NSMenu's own size for the items.
struct InlineMenuMetrics {
    static let padding: CGFloat = 5
    static let rowHeight: CGFloat = 24
    static let subtitledRowHeight: CGFloat = 38
    static let imageWidth: CGFloat = 18
    static let textInset: CGFloat = 16
    static let stateWidth: CGFloat = 14
    static let cornerRadius: CGFloat = 10

    let size: CGSize
    let hasState: Bool
    let hasImage: Bool

    @MainActor
    init(_ items: [RegisterMenuItem]) {
        hasState = items.contains(where: \.isChecked)
        hasImage = items.contains { $0.systemImage != nil }
        let menu = Self.menu(items).size
        let leading = Self.textInset + (hasState ? Self.stateWidth : 0) + (hasImage ? Self.imageWidth : 0)
        let text = items.map { item in
            max(
                Self.width(item.title, NSFont.menuFont(ofSize: 0)),
                item.subtitle.map { Self.width($0, NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)) } ?? 0)
        }
        size = CGSize(width: max(menu.width, leading + (text.max() ?? 0) + Self.textInset), height: menu.height)
    }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    var textLeading: CGFloat {
        Self.textInset + (hasState ? Self.stateWidth : 0) + (hasImage ? Self.imageWidth : 0)
    }

    @MainActor
    private static func menu(_ items: [RegisterMenuItem]) -> NSMenu {
        let menu = NSMenu()
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let children):
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.submenu = self.menu(children)
                menu.addItem(entry)
            case .title, .action:
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.state = item.isChecked ? .on : .off
                entry.subtitle = item.subtitle
                if let symbol = item.systemImage {
                    entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                menu.addItem(entry)
            }
        }
        return menu
    }
}

private struct InlineMenuView: View {
    let items: [RegisterMenuItem]
    let metrics: InlineMenuMetrics

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InlineMenuMetrics.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                row(item)
            }
        }
        .padding(.vertical, InlineMenuMetrics.padding)
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
        .font(Font(NSFont.menuFont(ofSize: 0)))
        .background(MenuMaterial().clipShape(shape))
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
    }

    @ViewBuilder
    private func row(_ item: RegisterMenuItem) -> some View {
        switch item.kind {
        case .separator:
            Rectangle().fill(.separator).frame(height: 1)
                .padding(.horizontal, InlineMenuMetrics.textInset)
                .frame(height: 11)
        default:
            ZStack(alignment: .leading) {
                if item.isChecked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: InlineMenuMetrics.stateWidth)
                        .offset(x: InlineMenuMetrics.textInset - 4)
                }
                if let symbol = item.systemImage {
                    Image(systemName: symbol)
                        .foregroundStyle(titleStyle(item))
                        .frame(width: InlineMenuMetrics.imageWidth - 6)
                        .offset(x: metrics.textLeading - InlineMenuMetrics.imageWidth)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.title).foregroundStyle(titleStyle(item))
                    if let subtitle = item.subtitle {
                        Text(verbatim: subtitle)
                            .font(Font(NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)))
                            .foregroundStyle(item.isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    }
                }
                .lineLimit(1)
                .offset(x: metrics.textLeading)
                if case .submenu = item.kind {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, InlineMenuMetrics.textInset - 2)
                }
            }
            .foregroundStyle(item.isEnabled && item.kind != .title ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(
                width: metrics.size.width,
                height: item.subtitle == nil ? InlineMenuMetrics.rowHeight : InlineMenuMetrics.subtitledRowHeight,
                alignment: .leading)
        }
    }
}

private func titleStyle(_ item: RegisterMenuItem) -> AnyShapeStyle {
    guard item.isEnabled, item.kind != .title else { return AnyShapeStyle(.tertiary) }
    return item.isDestructive ? AnyShapeStyle(Color(nsColor: .systemRed)) : AnyShapeStyle(.primary)
}

private struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
