import AppKit
import SwiftUI

/// The open notices as chips, then the undo notifier.
struct RegisterNotifierChips: View {
    static let fade = AnyTransition.opacity.animation(.motion(RegisterEffects.notifierFade))

    let notifiers: RegisterNotifierController

    var body: some View {
        let list = notifiers.list
        HStack(spacing: 6) {
            ForEach(list) { notifier in
                Group {
                    if notifier.kind == .undo {
                        UndoNotifier(notifier: notifier, notifiers: notifiers).layoutPriority(1)
                    } else {
                        NotifierView(notifier: notifier) { notifiers.clicked(notifier.kind) }
                            .toolTip(notifier.tooltip)
                    }
                }
                .transition(Self.fade)
            }
        }
    }
}

/// A small capsule: one symbol, the message and a link if any; a click anywhere on it acts.
struct NotifierView: View {
    let notifier: RegisterNotifier
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: Self.symbolName(notifier.kind))
                    .foregroundStyle(Self.tint(notifier.kind))
                if !notifier.text.isEmpty {
                    Text(verbatim: notifier.text).lineLimit(1).truncationMode(.tail)
                }
                if let link = notifier.link {
                    Text(verbatim: link).foregroundStyle(.link).fixedSize()
                }
            }
            .font(ThemeFont.body.font)
            .foregroundStyle(notifier.kind == .undo ? ThemeColor.text : Self.tint(notifier.kind))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Self.tint(notifier.kind).opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(Self.accessibilityLabel(notifier))
    }

    static func accessibilityLabel(_ notifier: RegisterNotifier) -> String {
        [notifier.text, notifier.link ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func symbolName(_ kind: RegisterNotifier.Kind) -> String {
        switch kind {
        case .error: "xmark.octagon.fill"
        case .warning: StatusSymbol.warning
        case .reminder: "circle.fill"
        case .undo: "arrow.uturn.backward"
        }
    }

    static func tint(_ kind: RegisterNotifier.Kind) -> Color {
        switch kind {
        case .error: ThemeColor.negative
        case .warning: ThemeColor.warning
        case .reminder: ThemeColor.accent
        case .undo: ThemeColor.secondaryText
        }
    }
}

/// The undo notifier goes away on the next mouse-down anywhere except on itself.
private struct UndoNotifier: View {
    let notifier: RegisterNotifier
    let notifiers: RegisterNotifierController
    @State private var isHovered = false
    @State private var monitor: Any?

    var body: some View {
        NotifierView(notifier: notifier) { notifiers.clicked(.undo) }
            .onHover { isHovered = $0 }
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                if !isHovered { notifiers.dismissUndo() }
            }
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
