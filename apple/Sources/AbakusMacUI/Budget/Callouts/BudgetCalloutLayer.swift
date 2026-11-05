import AbakusCore
import AbakusUI
import AppKit
import SwiftUI

struct BudgetCalloutLayer: View {
    static let fadeOut: TimeInterval = 0.15

    let model: BudgetViewModel
    let anchor: Anchor<CGRect>?
    @State private var bubbleFrame: CGRect?
    @State private var fadingFrame: CGRect?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let fadingFrame {
                    // A fading popover takes the clicks meant for it without acting on them.
                    Color.clear
                        .frame(width: fadingFrame.width, height: fadingFrame.height)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .offset(x: fadingFrame.minX, y: fadingFrame.minY)
                }
                if let popup = model.presentedPopup {
                    BudgetCalloutHost(model: model, popup: popup, owner: anchor.map { proxy[$0] }, bounds: proxy.size)
                        .id(popup)
                        .transition(
                            .asymmetric(
                                insertion: .identity, removal: .opacity.animation(.linear(duration: Self.fadeOut))))
                }
            }
        }
        .onPreferenceChange(BudgetCalloutFrameKey.self) { frame in
            if let frame { bubbleFrame = frame }
        }
        .onChange(of: model.presentedPopup) {
            guard let bubbleFrame else { return }
            fadingFrame = bubbleFrame
            self.bubbleFrame = nil
        }
        .task(id: fadingFrame) {
            guard fadingFrame != nil, (try? await Task.sleep(for: .seconds(Self.fadeOut))) != nil else { return }
            fadingFrame = nil
        }
    }
}

struct BudgetCalloutFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// A popover stays where it opened, even when its control scrolls away or hides.
private struct BudgetCalloutHost: View {
    let model: BudgetViewModel
    let popup: BudgetPopup
    let owner: CGRect?
    let bounds: CGSize
    @State private var openedAt: CGRect?

    var body: some View {
        Group {
            if let owner = openedAt ?? owner {
                callout(popup, owner: owner, bounds: bounds)
            }
        }
        .onAppear { openedAt = openedAt ?? owner }
        .onChange(of: owner) { openedAt = openedAt ?? owner }
    }

    @ViewBuilder
    private func callout(_ popup: BudgetPopup, owner: CGRect, bounds: CGSize) -> some View {
        let callouts = model.callouts
        switch popup {
        case .editCategory, .category:
            if let form = callouts.category {
                placer(owner, bounds) { BudgetCategoryPopover(controller: callouts, form: form) }
            }
        case .outflowSummary:
            if let summary = callouts.summary {
                placer(owner, bounds) { BudgetSummaryPopover(controller: callouts, summary: summary) }
            }
        case .available:
            if let form = callouts.availableForm {
                placer(owner, bounds, background: AnyShapeStyle(ThemeColor.groupBand)) {
                    BudgetAvailablePopover(controller: callouts, form: form)
                }
            }
        case .monthMenu(let month):
            BudgetMonthMenuPresenter(
                controller: callouts, month: month, location: CGPoint(x: owner.minX, y: owner.maxY + 1))
        }
    }

    private func placer<Content: View>(
        _ owner: CGRect, _ bounds: CGSize, background: AnyShapeStyle = AnyShapeStyle(ThemeColor.windowBackground),
        @ViewBuilder content: () -> Content
    ) -> some View {
        BudgetPopoverPlacer(
            controller: model.callouts, popup: popup, owner: owner, bounds: bounds, background: background,
            content: content)
    }
}

/// Shows once SwiftUI has measured the content, since the popover's place depends on its size; content taller than
/// the window scrolls.
private struct BudgetPopoverPlacer<Content: View>: View {
    static var windowMargin: CGFloat { 10 }

    let controller: BudgetCalloutController
    let popup: BudgetPopup
    let owner: CGRect
    let bounds: CGSize
    let background: AnyShapeStyle
    @ViewBuilder let content: Content
    @State private var contentSize: CGSize?

    var body: some View {
        let (placement, shown) = layout()
        let controller = controller
        let popup = popup
        ZStack(alignment: .topLeading) {
            // A fading popover keeps its monitor until it is gone, so it must not act for the next one.
            WindowEventMonitor(onEscape: { controller.isShowing(popup) && controller.escapePressed() }) { point in
                if controller.isShowing(popup), !placement.frame.contains(point) { controller.mouseDownOutside() }
            }
            .frame(width: bounds.width, height: bounds.height)
            PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset, background: background) {
                ScrollView(.vertical) {
                    content
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) {
                            $0.size
                        } action: {
                            contentSize = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: shown?.width, height: shown?.height, alignment: .leading)
            }
            .fixedSize()
            .offset(x: placement.frame.minX, y: placement.frame.minY)
            .opacity(contentSize == nil ? 0 : 1)
            .animation(.linear(duration: BudgetCalloutLayer.fadeOut), value: contentSize == nil)
        }
        .preference(key: BudgetCalloutFrameKey.self, value: contentSize == nil ? nil : placement.frame)
    }

    /// The popover's place and the size its scrolling content shows; a legacy scroller needs room beside it.
    private func layout() -> (PopoverPlacement, CGSize?) {
        guard let contentSize else { return (place(.zero), nil) }
        var shown = contentSize
        var natural = PopoverMetrics.size(content: shown)
        var placement = place(natural)
        if placement.frame.height < natural.height, NSScroller.preferredScrollerStyle == .legacy {
            shown.width += NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            natural = PopoverMetrics.size(content: shown)
            placement = place(natural)
        }
        shown.height -= natural.height - placement.frame.height
        return (placement, shown)
    }

    private func place(_ size: CGSize) -> PopoverPlacement {
        let margin = Self.windowMargin
        let area = CGSize(width: bounds.width - 2 * margin, height: bounds.height - 2 * margin)
        var placement = PopoverPlacement.place(
            size, beside: owner.offsetBy(dx: -margin, dy: -margin), on: .below, in: area
        ).fitting(in: area)
        placement.frame = placement.frame.offsetBy(dx: margin, dy: margin)
        return placement
    }
}

private struct BudgetMonthMenuPresenter: NSViewRepresentable {
    let controller: BudgetCalloutController
    let month: DateWithoutTime
    let location: CGPoint

    func makeNSView(context: Context) -> OriginView { OriginView() }

    func updateNSView(_ view: OriginView, context: Context) {
        guard !view.hasPresented else { return }
        view.hasPresented = true
        let items = controller.monthMenu(month: month)
        let presenter = context.environment.menuPresenter
        let controller = controller
        let month = month
        let location = location
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            presenter.present(items, location, view) { action in
                controller.monthMenuChosen(action, month: month)
            }
            controller.monthMenuClosed()
        }
    }

    final class OriginView: NSView {
        var hasPresented = false

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
