import AbakusCore
import AppKit
import SwiftUI

/// The search suggestions in the look of a system menu; the highlight follows the arrow keys, not the mouse.
struct SearchSuggestionMenu: View {
    static let width: CGFloat = 350
    static let rowHeight: CGFloat = 22
    static let visibleRows = 20
    static let padding: CGFloat = 5
    static let prefixWidth: CGFloat = 75
    static let cornerRadius: CGFloat = 8

    let search: RegisterSearchController
    let state: SearchDropDownState

    static func size(itemCount: Int) -> CGSize {
        CGSize(width: width, height: CGFloat(min(itemCount, visibleRows)) * rowHeight + 2 * padding)
    }

    var body: some View {
        let size = Self.size(itemCount: state.items.count)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        SuggestionRow(item: item, isHighlighted: state.highlighted == index)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { search.pickSuggestion(at: index) }
                    }
                }
                .padding(.vertical, Self.padding)
            }
            .scrollIndicators(state.items.count > Self.visibleRows ? .automatic : .never)
            .onChange(of: state.highlighted) {
                if let index = state.highlighted { proxy.scrollTo(state.items[index].id) }
            }
        }
        .frame(width: size.width, height: size.height)
        .systemMenuChrome(cornerRadius: Self.cornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suchvorschläge")
    }

    private struct SuggestionRow: View {
        let item: RegisterSearchSuggestion
        let isHighlighted: Bool

        var body: some View {
            HStack(spacing: 6) {
                Text(verbatim: item.prefix.trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(ThemeColor.selectedText) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .frame(width: SearchSuggestionMenu.prefixWidth, alignment: .trailing)
                if let symbol = item.icon?.symbol {
                    Image(systemName: symbol.name)
                        .foregroundStyle(isHighlighted ? ThemeColor.selectedText : symbol.color)
                        .frame(width: 16)
                        .accessibilityLabel(symbol.label)
                }
                description
                    .padding(.leading, CGFloat(item.indent))
                Spacer(minLength: 0)
            }
            .font(ThemeFont.body.font)
            .padding(.horizontal, 6)
            .frame(height: SearchSuggestionMenu.rowHeight)
            .background {
                if isHighlighted { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
            }
            .padding(.horizontal, SearchSuggestionMenu.padding)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        }

        @ViewBuilder
        private var description: some View {
            if item.isBlank {
                Text(verbatim: item.description)
                    .italic()
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(ThemeColor.selectedText) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            } else {
                Text(TextMarkup.attributed(item.description))
                    .foregroundStyle(isHighlighted ? ThemeColor.selectedText : ThemeColor.text)
                    .lineLimit(1)
            }
        }
    }
}

extension SearchSuggestionIcon {
    var symbol: StatusSymbol? {
        switch self {
        case .calendarMonth, .calendarSelect, .calendarSpan:
            StatusSymbol(name: "calendar", color: ThemeColor.secondaryText, label: "Datum")
        case .outflow: StatusSymbol(name: "minus.circle", color: ThemeColor.secondaryText, label: "Ausgang")
        case .inflow: StatusSymbol(name: "plus.circle", color: ThemeColor.secondaryText, label: "Eingang")
        case .cleared(let status): status.symbol(reconciling: false)
        }
    }
}

/// A child window under the search field, so the menu floats over the toolbar edge and never takes the focus.
@MainActor
final class SearchSuggestionWindow {
    private var panel: NSPanel?
    private var host: FirstClickHostingView?

    func show(_ state: SearchDropDownState?, search: RegisterSearchController, below field: NSView) {
        guard let state, let window = field.window else {
            close()
            return
        }
        let size = SearchSuggestionMenu.size(itemCount: state.items.count)
        let panel = self.panel ?? makePanel()
        host?.rootView = AnyView(SearchSuggestionMenu(search: search, state: state))
        let fieldFrame = window.convertToScreen(field.convert(field.bounds, to: nil))
        let preferredX = fieldFrame.minX - SearchSuggestionMenu.prefixWidth + 20
        let x = min(max(preferredX, window.frame.minX), window.frame.maxX - size.width)
        panel.setFrame(
            NSRect(x: x, y: fieldFrame.minY - 3 - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
    }

    func close() {
        guard let panel, panel.parent != nil || panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        let host = FirstClickHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = host
        self.panel = panel
        self.host = host
        return panel
    }

    private final class FirstClickHostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
