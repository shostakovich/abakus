import AbakusCore
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
        case .editCategory:
            if let form = callouts.category {
                placer(owner, bounds) { BudgetCategoryPopover(controller: callouts, form: form) }
            }
        case .outflowSummary, .incomeSummary:
            if let summary = callouts.summary {
                placer(owner, bounds) { BudgetSummaryPopover(controller: callouts, summary: summary) }
            }
        case .outflowHelp:
            if let help = callouts.outflowHelp {
                placer(owner, bounds) { BudgetOutflowHelpPopover(controller: callouts, help: help) }
            }
        case .available:
            if let form = callouts.availableForm {
                placer(owner, bounds) { BudgetAvailablePopover(controller: callouts, form: form) }
            }
        case .assignToCategory:
            if let form = callouts.assignForm {
                placer(owner, bounds) { BudgetAssignPopover(controller: callouts, form: form) }
            }
        case .monthQuickBudget(let month):
            BudgetQuickBudgetMenuPresenter(
                controller: callouts, month: month, location: CGPoint(x: owner.minX, y: owner.maxY + 1))
        }
    }

    private func placer<Content: View>(_ owner: CGRect, _ bounds: CGSize, @ViewBuilder content: () -> Content)
        -> some View
    {
        BudgetPopoverPlacer(controller: model.callouts, popup: popup, owner: owner, bounds: bounds, content: content)
    }
}

/// Shows once SwiftUI has measured the content, since the popover's place depends on its size; content taller than
/// the window scrolls.
private struct BudgetPopoverPlacer<Content: View>: View {
    let controller: BudgetCalloutController
    let popup: BudgetPopup
    let owner: CGRect
    let bounds: CGSize
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
            PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset) {
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
        guard let contentSize else {
            return (PopoverPlacement.place(.zero, beside: owner, on: .below, in: bounds), nil)
        }
        var shown = contentSize
        var natural = PopoverMetrics.size(content: shown)
        var placement = PopoverPlacement.place(natural, beside: owner, on: .below, in: bounds).fitting(in: bounds)
        if placement.frame.height < natural.height, NSScroller.preferredScrollerStyle == .legacy {
            shown.width += NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            natural = PopoverMetrics.size(content: shown)
            placement = PopoverPlacement.place(natural, beside: owner, on: .below, in: bounds).fitting(in: bounds)
        }
        shown.height -= natural.height - placement.frame.height
        return (placement, shown)
    }
}

private struct BudgetQuickBudgetMenuPresenter: NSViewRepresentable {
    let controller: BudgetCalloutController
    let month: DateWithoutTime
    let location: CGPoint

    func makeNSView(context: Context) -> OriginView { OriginView() }

    func updateNSView(_ view: OriginView, context: Context) {
        guard !view.hasPresented else { return }
        view.hasPresented = true
        let items = controller.quickBudgetMenu(month: month)
        let presenter = context.environment.menuPresenter
        let controller = controller
        let month = month
        let location = location
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            presenter.present(items, location, view) { action in
                controller.quickBudgetMenuChosen(action, month: month)
            }
            controller.quickBudgetMenuClosed()
        }
    }

    final class OriginView: NSView {
        var hasPresented = false

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
