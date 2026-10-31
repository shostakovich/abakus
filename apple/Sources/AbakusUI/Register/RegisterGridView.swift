import AbakusCore
import AppKit
import SwiftUI

struct RegisterGridView: View {
    let owner: any RegisterGridOwner
    let size: CGSize
    @State private var scrollPosition = ScrollPosition()
    @State private var scroll = ScrollMetricsBox()
    @State private var placed = PlacedList()
    @State private var keepsEnd: Bool
    /// A former account's grid fades out showing the next account's rows.
    @State private var accountKey: String?
    @FocusState private var isFocused: Bool

    init(owner: any RegisterGridOwner, size: CGSize) {
        self.owner = owner
        self.size = size
        _keepsEnd = State(initialValue: !owner.startsAtTop)
        _accountKey = State(initialValue: owner.mainGrid?.accountKey)
    }

    private var grid: RegisterGridController { owner.grid }
    private var main: RegisterViewModel? { owner.mainGrid }

    var body: some View {
        let layout = owner.columnLayout(gridWidth: size.width)
        let rows = owner.rows
        let addRow = grid.addRowPlacement(gridHeight: size.height)
        let listHeight = addRow.listHeight(gridHeight: size.height)
        let contentHeight = grid.listContentHeight(viewport: listHeight)
        let bodyHeight = max(0, size.height - RegisterMetrics.headerHeight)
        VStack(spacing: 0) {
            RegisterGridHeader(owner: owner, layout: layout)
                // The column menu opens straight below the mouse, unlike the row menus.
                .onSecondaryClick(offset: CGSize(width: 0, height: 1), perform: grid.register.performMenuAction) { _ in
                    owner.headerContextMenu()
                }
            ZStack(alignment: .topLeading) {
                list(rows: rows, layout: layout, height: listHeight, contentHeight: contentHeight)
                    .onSecondaryClick(perform: grid.register.performMenuAction) { point in
                        let items = grid.contextMenu(atY: point.y, scrollOffset: scroll.metrics.offset)
                        if main == nil, items?.isEmpty == false { isFocused = true }
                        return items
                    }
                if let editor = grid.editor, editor.mode == .new {
                    EditRowView(editor: editor, layout: layout, row: nil, main: main)
                        .offset(y: addRow.y - RegisterMetrics.headerHeight)
                }
            }
            .frame(width: size.width, height: bodyHeight, alignment: .topLeading)
            .clipped()
        }
        .background(ThemeColor.contentBackground)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .pageUp, .pageDown, .home, .end]) { press in
            if grid.editor != nil {
                guard press.key == .upArrow || press.key == .downArrow else { return .ignored }
                return grid.editorArrowPressed(press.key == .upArrow ? .up : .down) ? .handled : .ignored
            }
            guard let key = Self.navigationKey(press.key) else { return .ignored }
            let id = grid.navigationKeyPressed(
                key, extending: press.modifiers.contains(.shift), caretOnly: press.modifiers.contains(.command),
                pageRows: max(1, Int(listHeight / RegisterMetrics.rowHeight) - 1))
            if let id { reveal(.row(id)) }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard Self.deleteCharacters.contains(press.characters), grid.editor == nil else { return .ignored }
            owner.deleteKeyPressed()
            return .handled
        }
        .onKeyPress(keys: ["c", Self.f5]) { press in
            guard let main else { return .ignored }
            if press.key == Self.f5 {
                main.refreshSort()
                return .handled
            }
            guard press.modifiers.isEmpty, grid.editor == nil || grid.editor?.focus?.field == nil else {
                return .ignored
            }
            main.toggleClearedKeyPressed()
            return .handled
        }
        .onKeyPress(keys: [.return, .tab, .space, .escape, Self.f2]) { press in
            if let editor = grid.editor {
                let key: EditorKey? =
                    switch press.key {
                    case .return: .enter
                    case .tab: press.modifiers.contains(.shift) ? .backTab : .tab
                    case .space: .space
                    case .escape: .escape
                    default: nil
                    }
                guard let key else { return .ignored }
                return editor.handleKey(key) ? .handled : .ignored
            }
            guard press.key == .return || press.key == Self.f2 else { return .ignored }
            grid.editSelected()
            return .handled
        }
        .onChange(of: grid.editor?.focus) {
            switch grid.editor?.focus {
            case .button, .field(.main(.frequency)): isFocused = true
            default: break
            }
            if grid.editingId != nil { keepPlace() }
        }
        .onChange(of: grid.editor == nil) {
            if grid.editor == nil { isFocused = true }
        }
        .onChange(of: main?.gridFocusRequest) { isFocused = true }
        .onChange(of: main?.popup == nil) {
            if let main, main.popup == nil && !main.search.isFocused && grid.editor == nil { isFocused = true }
        }
        .onChange(of: grid.scrollRequest) {
            guard let request = grid.scrollRequest else { return }
            if grid.editor == nil { reveal(request.target) } else { keepPlace() }
        }
        .onChange(of: [listHeight, contentHeight]) { keepPlace() }
        .onChange(of: grid.editor?.rowHeight) { keepPlace() }
        .onAppear {
            record(grid.scrollMetrics(at: owner.startsAtTop ? 0 : .greatestFiniteMagnitude, viewport: viewport))
            if let request = grid.scrollRequest {
                reveal(request.target)
            } else if let offset = main?.savedScrollOffset() {
                show(grid.scrollMetrics(at: offset, viewport: viewport))
            }
            if let main, !main.search.isFocused && !grid.hasOpenEdit { isFocused = true }
        }
    }

    static func navigationKey(_ key: KeyEquivalent) -> RegisterNavigationKey? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        case .home: .home
        case .end: .end
        default: nil
        }
    }

    static let f2 = KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!))
    static let f5 = KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!))
    static let deleteCharacters: Set<String> = [
        "\u{7F}", "\u{8}", String(Character(UnicodeScalar(NSDeleteFunctionKey)!)),
    ]

    private var viewport: CGFloat {
        grid.addRowPlacement(gridHeight: size.height).listHeight(gridHeight: size.height)
    }

    private func reveal(_ target: RegisterScrollRequest.Target) {
        guard let list = grid.scrollMetrics(revealing: target, from: placed.list, viewport: viewport) else { return }
        show(list)
    }

    /// The size-change anchor moves the list, also through animated resizes; only an edit's reveal needs a scroll.
    private func keepPlace() {
        let list = grid.scrollMetrics(afterResizing: placed.list, to: viewport)
        if grid.editor == nil { record(list) } else { show(list) }
    }

    private func show(_ list: ScrollMetrics) {
        record(list)
        scrollPosition.scrollTo(y: list.offset)
    }

    private func record(_ list: ScrollMetrics) {
        placed.list = list
        placed.count += 1
        let end = grid.keepsEnd(list)
        if keepsEnd != end { keepsEnd = end }
        restoreIfDrifted()
    }

    private var isUserScrolling: Bool { placed.isUserScrolling || scrollPosition.isPositionedByUser }

    private var hasDrifted: Bool {
        scroll.metrics.hasSameSize(as: placed.list) && abs(scroll.metrics.offset - placed.list.offset) > 0.5
    }

    /// Also after a placement: its size can be on screen already, so no geometry change would report the drift.
    private func restoreIfDrifted() {
        guard !isUserScrolling, hasDrifted else { return }
        let count = placed.count
        DispatchQueue.main.async { restore(after: count) }
    }

    /// The scroll view clamps a resizing list to its old viewport and skips a position equal to the one it holds.
    private func restore(after count: Int) {
        guard placed.count == count, !isUserScrolling, hasDrifted else { return }
        scrollPosition.scrollTo(y: scroll.metrics.offset)
        DispatchQueue.main.async {
            guard placed.count == count, !isUserScrolling, hasDrifted else { return }
            scrollPosition.scrollTo(y: placed.list.offset)
        }
    }

    private func list(rows: [RegisterRow], layout: RegisterColumnLayout, height: CGFloat, contentHeight: CGFloat)
        -> some View
    {
        let extraHeight = grid.editRowExtraHeight
        let selection = grid.selection
        let editingId = grid.editingId
        let editor = grid.editor
        // A legacy scroller narrows the content; rows then give up the trailing column-menu slot instead of centring.
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        if let editor, row.id == editingId {
                            EditRowView(editor: editor, layout: layout, row: row, main: main)
                        } else {
                            RegisterRowView(
                                row: row, layout: layout, isSelected: selection.contains(row.transactionId),
                                owner: owner, onClick: { isFocused = true })
                        }
                    }
                }
                Color.clear
                    .frame(
                        height: max(0, contentHeight - CGFloat(rows.count) * RegisterMetrics.rowHeight - extraHeight))
            }
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(RowSnapBehavior(isOn: owner.snapsToRows))
        .defaultScrollAnchor(owner.startsAtTop ? .top : .bottom, for: .initialOffset)
        .defaultScrollAnchor(keepsEnd ? .bottom : .top, for: .sizeChanges)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y, contentHeight: geometry.contentSize.height,
                viewportHeight: geometry.containerSize.height)
        } action: { _, new in
            scroll.metrics = new
            if let main, main.accountKey == accountKey { main.saveScrollOffset(new.isAtEnd ? nil : new.offset) }
            if isUserScrolling { record(new) } else { restoreIfDrifted() }
        }
        .onScrollPhaseChange { _, phase in
            placed.isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .frame(width: layout.gridWidth, height: height)
    }
}

/// Where the grid last put the list or the user scrolled it; the scroll view drifts from it while the list resizes.
@MainActor
private final class PlacedList {
    var list = ScrollMetrics()
    /// Placements so far, so a queued restore yields to a newer one.
    var count = 0
    var isUserScrolling = false
}

/// Like Flex lists, a snapping grid scrolls by whole rows.
private struct RowSnapBehavior: ScrollTargetBehavior {
    let isOn: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isOn else { return }
        let maxOffset = max(0, context.contentSize.height - context.containerSize.height)
        target.rect.origin.y = RegisterGridController.snappedOffset(target.rect.origin.y, maxOffset: maxOffset)
    }
}
