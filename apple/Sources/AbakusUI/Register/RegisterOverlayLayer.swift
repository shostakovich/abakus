import AbakusCore
import SwiftUI

struct RegisterOverlayLayer: View {
    let model: RegisterViewModel
    let anchors: [RegisterAnchorID: Anchor<CGRect>]
    let toolbarAnchors: ToolbarAnchors

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rects = toolbarAnchors.frames(relativeTo: proxy.frame(in: .global).origin)
                .merging(anchors.mapValues { proxy[$0] }) { $1 }
            ZStack(alignment: .topLeading) {
                if let popup = model.popup, Self.closesOnOutsideClick(popup) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { model.closePopup() }
                } else {
                    Color.clear.allowsHitTesting(false)
                }
                if let popup = model.popup, let anchor = rects[popup.anchor] {
                    popupView(popup, anchor: anchor, size: size)
                }
                AnchoredMenuPresenter(
                    request: model.menuRequest,
                    location: model.menuRequest.flatMap { rects[$0.anchor] }.map {
                        CGPoint(x: $0.minX, y: $0.maxY + 1)
                    },
                    model: model
                )
                .frame(width: 0, height: 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    static func closesOnOutsideClick(_ popup: RegisterPopup) -> Bool {
        switch popup {
        case .runningBalance, .scheduledCallout: false
        default: true
        }
    }

    @ViewBuilder
    private func popupView(_ popup: RegisterPopup, anchor: CGRect, size: CGSize) -> some View {
        switch popup {
        case .approveReject, .removeCategory:
            AnchoredPopover(side: .trailing, anchor: anchor, container: size) { StatusOptionsPopover(model: model) }
        case .needsCategory:
            AnchoredPopover(side: .trailing, anchor: anchor, container: size) { NeedsCategoryPopover(model: model) }
        case .timeframe:
            AnchoredPopover(side: .below, anchor: anchor, container: size) { TimeframePopover(search: model.search) }
        case .runningBalance(let rowId):
            if let info = model.runningBalanceInfo(for: rowId) {
                AnchoredPopover(side: .above, anchor: anchor, container: size) { RunningBalancePopover(info: info) }
                    .allowsHitTesting(false)
            }
        case .scheduledCallout(let callout):
            AnchoredPopover(side: .above, anchor: anchor, container: size) {
                ScheduledCalloutPopover(callout: callout) { model.closePopup() }
            }
        }
    }
}

/// The popovers take keyboard focus so Escape closes them.
private struct EscapeCloses: ViewModifier {
    let action: () -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                action()
                return .handled
            }
            .onAppear { isFocused = true }
    }
}

extension View {
    func closesOnEscape(_ action: @escaping () -> Void) -> some View {
        modifier(EscapeCloses(action: action))
    }
}
