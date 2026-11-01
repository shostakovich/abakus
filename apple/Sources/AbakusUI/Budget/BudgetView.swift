import AbakusCore
import AppKit
import SwiftUI

public struct BudgetView: View {
    static let panelSpace = "BudgetPanel"

    let model: BudgetViewModel
    @FocusState private var isKeySinkFocused: Bool

    public init(model: BudgetViewModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = model.layout(panelSize: proxy.size)
            ZStack(alignment: .topLeading) {
                keySink
                BudgetPanelContent(model: model, layout: layout)
                BudgetPopupsLayer(model: model)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .coordinateSpace(name: Self.panelSpace)
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            model.panelSize = $0
        }
        .background(ThemeColor.windowBackground)
        .toolbar { BudgetToolbar(model: model) }
        // The toolbar shows "Budget" instead of the window title, which keeps its width for the timeline.
        .toolbar(removing: .title)
        .overlay {
            if model.editor != nil || model.quickBudget != nil || model.calculator != nil {
                WindowEventMonitor { model.mouseDown(at: $0) }
            }
        }
        .onChange(of: model.isHeaderExpanded) { _, expanded in
            withAnimation(.motion(BudgetStyle.headerResize)) { model.headerProgress = expanded ? 1 : 0 }
        }
        .task(id: model.drag?.autoScrolls == true) {
            while model.drag?.autoScrolls == true, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                model.autoScrollTick()
            }
        }
        .onChange(of: model.panelFocusRequest) { if !model.isCoveredByModal { isKeySinkFocused = true } }
        .onChange(of: model.editor == nil) { if model.takesKeyFocusBack { isKeySinkFocused = true } }
        .onChange(of: model.dialogs.isPresenting) { if model.takesKeyFocusBack { isKeySinkFocused = true } }
        .onAppear { isKeySinkFocused = true }
    }

    private var keySink: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable()
            .focused($isKeySinkFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                guard let key = Self.key(press) else { return .ignored }
                return model.panelKey(key) ? .handled : .ignored
            }
            .allowsHitTesting(false)
    }

    static func key(_ press: KeyPress) -> BudgetCellKey? {
        switch press.key {
        case .return: .enter
        case .escape: .escape
        case .delete: .backspace
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        case .upArrow: .up
        case .downArrow: .down
        case .tab: press.modifiers.contains(.shift) ? .backTab : .tab
        default: press.characters.isEmpty ? nil : .character(press.characters)
        }
    }
}

private struct BudgetPanelContent: View {
    let model: BudgetViewModel
    let layout: BudgetLayout

    var body: some View {
        let table = layout.tableFrame
        BudgetTable(model: model, layout: layout, months: model.shownMonths.compactMap(model.month))
            .offset(x: table.minX, y: table.minY)
            .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .topLeading)
    }
}

private struct BudgetTable: View {
    let model: BudgetViewModel
    let layout: BudgetLayout
    let months: [BudgetMonth]

    var body: some View {
        let size = layout.tableFrame.size
        let header = layout.headerHeight
        let shape = RoundedRectangle(cornerRadius: BudgetStyle.tableCornerRadius)
        let tints = months.indices.map(layout.availableColumn(at:))
        ZStack(alignment: .topLeading) {
            ForEach(tints, id: \.minX) { tint in
                Rectangle().fill(ThemeColor.availableTint)
                    .frame(width: tint.width, height: tint.height)
                    .offset(x: tint.minX, y: tint.minY)
            }
            BudgetCategoryHeaderCell(model: model, width: layout.categoryWidth, height: header)
            ForEach(Array(months.enumerated()), id: \.element.month) { index, month in
                BudgetMonthHeader(
                    model: model, month: month, width: layout.columnWidth, cells: layout.cells(at: index),
                    detailsHeight: layout.headerDetailsHeight, progress: layout.headerProgress
                )
                .frame(height: header, alignment: .top)
                .clipped()
                .offset(x: layout.columnX(index))
            }
            Rectangle().fill(ThemeColor.separator).frame(width: size.width, height: 1).offset(y: header - 1)
            rows(tints: tints)
                .frame(width: size.width, height: layout.viewportHeight, alignment: .topLeading)
                .clipped()
                .offset(y: header)
            ForEach(0..<months.count, id: \.self) { index in
                Rectangle().fill(ThemeColor.separator)
                    .frame(width: 1, height: size.height)
                    .offset(x: layout.separatorX(index) - 0.5)
                    .allowsHitTesting(false)
            }
            BudgetColumnGrabber(model: model, height: size.height)
                .offset(x: layout.categoryWidth)
            BudgetScroller(
                contentHeight: model.contentHeight, offset: model.scrollOffset, onScroll: model.scroll(to:)
            )
            .frame(width: size.width, height: layout.viewportHeight)
            .offset(y: header)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(ThemeColor.contentBackground)
        .clipShape(shape)
        .overlay { shape.strokeBorder(ThemeColor.separator, lineWidth: 1) }
    }

    private func rows(tints: [CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            BudgetRowBackgrounds(
                groups: model.groups, offset: model.scrollOffset, width: layout.tableWidth, tints: tints)
            BudgetCategoryRowsView(model: model, width: layout.categoryWidth)
            ForEach(Array(months.enumerated()), id: \.element.month) { index, month in
                BudgetMonthRowsView(model: model, month: month, cells: layout.cells(at: index))
                    .frame(width: layout.columnWidth, alignment: .topLeading)
                    .offset(x: layout.columnX(index))
            }
        }
    }
}

private struct BudgetColumnGrabber: View {
    let model: BudgetViewModel
    let height: CGFloat
    @GestureState private var isResizing = false

    var body: some View {
        Color.clear
            .frame(width: BudgetMetrics.separatorWidth, height: height)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BudgetView.panelSpace))
                    .updating($isResizing) { _, state, _ in state = true }
                    .onChanged { value in
                        if model.resizeOrigin == nil { model.beginColumnResize(atX: value.startLocation.x) }
                        model.columnResizeMoved(toX: value.location.x)
                    }
                    .onEnded { _ in model.endColumnResize() }
            )
            .onChange(of: isResizing) { _, resizing in
                if !resizing { model.endColumnResize() }
            }
            .accessibilityHidden(true)
    }
}

private struct BudgetPopupsLayer: View {
    let model: BudgetViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if let list = model.quickBudget, let frame = model.quickBudgetFrame() {
                BudgetQuickBudgetListView(model: model, list: list)
                    .offset(x: frame.minX, y: frame.minY)
            }
            if let state = model.calculator, let placement = model.calculatorPlacement() {
                PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset) {
                    CalculatorPopover(
                        display: state.calculator.display,
                        decimalSeparator: model.formatter.currencyLocale.decimalSeparator,
                        onPress: model.calculatorPress, onOK: model.calculatorOK, onCancel: model.calculatorCancel)
                }
                .offset(x: placement.frame.minX, y: placement.frame.minY)
            }
            if let drag = model.drag, drag.isActive {
                proxy(drag)
            }
        }
    }

    @ViewBuilder
    private func proxy(_ drag: BudgetDrag) -> some View {
        let origin = model.categoryRowsOrigin
        let width = model.layout.categoryWidth
        Group {
            if let group = model.groups.first(where: { $0.id == drag.rowId }) {
                BudgetCategoryHeaderRow(model: model, group: group, width: width, isProxy: true)
            } else if let row = model.groups.visibleRows.first(where: { $0.id == drag.rowId }) {
                BudgetCategorySubRow(model: model, row: row, width: width, isProxy: true)
            }
        }
        .opacity(0.7)
        .allowsHitTesting(false)
        .offset(x: origin.x + drag.proxyOffset.width, y: origin.y + drag.proxyOffset.height)
    }
}

/// The system scroller over the rows; the model keeps the offset, so only the scroller and the wheel reach it.
struct BudgetScroller: NSViewRepresentable {
    let contentHeight: CGFloat
    let offset: CGFloat
    let onScroll: @MainActor (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ScrollerView {
        let view = ScrollerView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = true
        view.verticalScrollElasticity = .none
        view.horizontalScrollElasticity = .none
        view.verticalLineScroll = BudgetMetrics.rowHeight
        view.documentView = FlippedView()
        view.contentView.drawsBackground = false
        view.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(view.contentView)
        return view
    }

    func updateNSView(_ view: ScrollerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onScroll = onScroll
        coordinator.isApplying = true
        defer { coordinator.isApplying = false }
        view.documentView?.frame = CGRect(x: 0, y: 0, width: 1, height: contentHeight)
        if abs(view.contentView.bounds.origin.y - offset) > 0.5 {
            view.contentView.scroll(to: NSPoint(x: 0, y: offset))
            view.reflectScrolledClipView(view.contentView)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: @MainActor (CGFloat) -> Void = { _ in }
        var isApplying = false

        func observe(_ clipView: NSClipView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification,
                object: clipView)
        }

        @objc func boundsChanged(_ notification: Notification) {
            guard !isApplying, let clipView = notification.object as? NSClipView else { return }
            onScroll(clipView.bounds.origin.y)
        }
    }

    /// Takes the wheel and clicks on the scroller; every other click reaches the rows beneath.
    final class ScrollerView: NSScrollView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let hit = super.hitTest(point) else { return nil }
            if NSApp.currentEvent?.type == .scrollWheel { return hit }
            if let scroller = verticalScroller, hit === scroller || hit.isDescendant(of: scroller) { return hit }
            return nil
        }
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
