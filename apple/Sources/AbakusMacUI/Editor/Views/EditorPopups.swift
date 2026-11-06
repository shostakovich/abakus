import AbakusCore
import AbakusUI
import AppKit
import SwiftUI

struct EditorPopupsLayer: View {
    let editor: TransactionEditor
    let anchors: [EditorFieldID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rects = anchors.mapValues { proxy[$0] }
            let frames = Self.popupFrames(editor: editor, anchors: rects, size: size)
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if editor.hasOpenPopup {
                    OutsideClickMonitor(areas: Self.keepOpenAreas(editor: editor, anchors: rects, size: size)) {
                        editor.closePopups()
                    }
                    .frame(width: 0, height: 0)
                }
                menus(rects)
                if let list = editor.dropDown, let frame = frames.dropDown {
                    DropDownListView(editor: editor, state: list, width: frame.width, formatter: editor.formatter)
                        .offset(x: frame.minX, y: frame.minY)
                }
                if let placement = frames.calendar {
                    PopoverChrome(arrowEdge: placement.arrowEdge, arrowOffset: placement.arrowOffset) {
                        GraphicalDatePicker(
                            date: editor.clone.date, locale: editor.formatter.dateLocale,
                            onPick: editor.calendarDatePicked)
                    }
                    .offset(x: placement.frame.minX, y: placement.frame.minY)
                }
                if let callout = editor.dateCallout, let field = rects[.main(.date)] {
                    dateCallout(callout, field: field, size: size)
                }
                if let error = editor.amountError, let anchor = anchors[error.field] {
                    BudgetAmountErrorBubble(error: error.message, anchor: anchor)
                }
            }
        }
    }

    @ViewBuilder
    private func menus(_ rects: [EditorFieldID: CGRect]) -> some View {
        let frequencyField = rects[.main(.frequency)]
        PopUpMenu(
            items: editor.isFrequencyListOpen && frequencyField != nil
                ? RegisterMenuItem.frequencyMenu(selected: editor.frequency) : nil,
            location: frequencyField.map { CGPoint(x: $0.minX, y: $0.maxY + 1) } ?? .zero,
            perform: editor.menuAction, dismiss: editor.frequencyListDismissed
        )
        .frame(width: 0, height: 0)
    }

    private func dateCallout(_ callout: EditorDateCallout, field: CGRect, size: CGSize) -> some View {
        let width: CGFloat = 375
        let x = min(max(0, field.midX - 57), max(0, size.width - width))
        return Group {
            if editor.isScheduled {
                PopoverCallout(
                    title: callout.title, message: callout.message, width: width, tailX: field.midX - x,
                    tailAtBottom: true
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: max(0, field.minY), alignment: .bottom)
                .offset(x: x)
            } else {
                PopoverCallout(title: callout.title, message: callout.message, width: width, tailX: field.midX - x)
                    .offset(x: x, y: field.maxY)
            }
        }
        .allowsHitTesting(false)
    }

    struct PopupFrames {
        var dropDown: CGRect?
        var calendar: PopoverPlacement?

        var all: [CGRect] { [dropDown, calendar?.frame].compactMap(\.self) }
    }

    static func popupFrames(editor: TransactionEditor, anchors: [EditorFieldID: CGRect], size: CGSize)
        -> PopupFrames
    {
        var frames = PopupFrames()
        if let list = editor.dropDown, let field = anchors[list.field] {
            let width = max(field.width, list.kind.minWidth)
            let height = DropDownListView.height(list)
            frames.dropDown = CGRect(
                x: min(field.minX, size.width - width), y: verticalPosition(field, height, size), width: width,
                height: height)
        }
        if editor.isCalendarOpen, let field = anchors[.main(.date)] {
            frames.calendar = PopoverPlacement.place(
                PopoverMetrics.size(content: GraphicalDatePicker.size), beside: field, on: .below, in: size)
        }
        return frames
    }

    /// The open popups and the cells that own them; the owners toggle their popup themselves.
    static func keepOpenAreas(editor: TransactionEditor, anchors: [EditorFieldID: CGRect], size: CGSize)
        -> [CGRect]
    {
        var owners: [CGRect] = []
        if let list = editor.dropDown, let field = anchors[list.field] { owners.append(field) }
        if editor.isCalendarOpen, let field = anchors[.main(.date)] { owners.append(field) }
        if editor.isFrequencyListOpen, let field = anchors[.main(.frequency)] { owners.append(field) }
        return popupFrames(editor: editor, anchors: anchors, size: size).all + owners
    }

    /// spark `mouseDownOutside`: the popups close and the click still reaches what is under it.
    static func closesPopups(at point: CGPoint, keeping areas: [CGRect]) -> Bool {
        !areas.contains { $0.contains(point) }
    }

    /// Below the field unless it only fits above.
    static func verticalPosition(_ field: CGRect, _ height: CGFloat, _ size: CGSize) -> CGFloat {
        let below = field.maxY + 2
        if size.height - below > height || field.minY <= height { return below }
        return field.minY - height - 2
    }
}

private struct OutsideClickMonitor: NSViewRepresentable {
    let areas: [CGRect]
    let onOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.areas = areas
        view.onOutside = onOutside
    }

    final class MonitorView: NSView {
        var areas: [CGRect] = []
        var onOutside: () -> Void = {}
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window else { return }
            let point = convert(event.locationInWindow, from: nil)
            if EditorPopupsLayer.closesPopups(at: point, keeping: areas) { onOutside() }
        }
    }
}

/// The graphical date picker; it never takes the keyboard, so typing stays in the date field.
struct GraphicalDatePicker: NSViewRepresentable {
    let date: DateWithoutTime
    let locale: FormatLocale
    let onPick: (DateWithoutTime) -> Void

    @MainActor static var size: CGSize {
        if let measured { return measured }
        let size = makePicker().fittingSize
        measured = size
        return size
    }

    @MainActor private static var measured: CGSize?

    private static func makePicker() -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.refusesFirstResponder = true
        return picker
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = Self.makePicker()
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.picked(_:))
        picker.setAccessibilityLabel("Datum")
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        let calendar = locale.calendar
        context.coordinator.calendar = calendar
        context.coordinator.onPick = onPick
        picker.calendar = calendar
        picker.locale = calendar.locale
        picker.timeZone = calendar.timeZone
        let value = date.date(in: calendar)
        if picker.dateValue != value { picker.dateValue = value }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        Self.size
    }

    @MainActor
    final class Coordinator: NSObject {
        var calendar = Calendar(identifier: .gregorian)
        var onPick: (DateWithoutTime) -> Void = { _ in }

        @objc func picked(_ sender: NSDatePicker) {
            onPick(DateWithoutTime(sender.dateValue, in: calendar))
        }
    }
}

struct PopoverCallout<Footer: View>: View {
    let title: String
    let message: String
    let width: CGFloat
    let tailX: CGFloat
    var tailAtBottom = false
    let footer: Footer

    init(
        title: String, message: String, width: CGFloat, tailX: CGFloat, tailAtBottom: Bool = false,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.message = message
        self.width = width
        self.tailX = tailX
        self.tailAtBottom = tailAtBottom
        self.footer = footer()
    }

    var body: some View {
        PopoverChrome(arrowEdge: tailAtBottom ? .bottom : .top, arrowOffset: tailX, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title)
                    .font(ThemeFont.headline.font)
                Text(TextMarkup.attributed(message))
                    .font(ThemeFont.body.font)
                    .fixedSize(horizontal: false, vertical: true)
                footer
            }
            .foregroundStyle(ThemeColor.text)
            .frame(width: width - 28, alignment: .leading)
        }
    }
}

extension PopoverCallout where Footer == EmptyView {
    init(title: String, message: String, width: CGFloat, tailX: CGFloat, tailAtBottom: Bool = false) {
        self.init(title: title, message: message, width: width, tailX: tailX, tailAtBottom: tailAtBottom) {
            EmptyView()
        }
    }
}

struct IncomeCheckAnchor {
    var row: Anchor<CGRect>
    var amount: RegisterColumnFrame
}

struct IncomeCheckAnchorKey: PreferenceKey {
    static let defaultValue: IncomeCheckAnchor? = nil

    static func reduce(value: inout IncomeCheckAnchor?, nextValue: () -> IncomeCheckAnchor?) {
        value = value ?? nextValue()
    }
}

struct IncomeCheckLayer: View {
    static let width: CGFloat = 470

    let model: RegisterViewModel
    let check: RegisterIncomeCheck
    let anchor: IncomeCheckAnchor

    var body: some View {
        GeometryReader { proxy in
            let row = proxy[anchor.row]
            let center = row.minX + anchor.amount.x + anchor.amount.width / 2
            let x = min(max(0, center - 60), proxy.size.width - Self.width)
            ZStack(alignment: .topLeading) {
                Color.clear
                PopoverCallout(
                    title: RegisterIncomeCheck.title, message: RegisterIncomeCheck.message, width: Self.width,
                    tailX: center - x
                ) {
                    HStack(spacing: 8) {
                        Button(RegisterIncomeCheck.swapTitle) { model.incomeCheckAnswered(swap: true) }
                            .buttonStyle(.borderedProminent)
                        Button(RegisterIncomeCheck.keepTitle) { model.incomeCheckAnswered(swap: false) }
                    }
                    .padding(.top, 6)
                }
                .offset(x: x, y: row.maxY)
            }
        }
    }
}
