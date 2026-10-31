import AppKit
import SwiftUI

struct RegisterNotifierBar: View {
    static let fade = AnyTransition.opacity.animation(.motion(RegisterEffects.notifierFade))

    let notifiers: RegisterNotifierController

    var body: some View {
        let list = notifiers.list
        let statuses = list.filter { $0.kind != .undo }
        let undo = list.first { $0.kind == .undo }
        HStack(spacing: 8) {
            ForEach(statuses) { notifier in
                NotifierView(notifier: notifier) { notifiers.clicked(notifier.kind) }
                    .transition(Self.fade)
            }
            Spacer(minLength: 0)
            if let undo {
                UndoNotifier(notifier: undo, notifiers: notifiers).layoutPriority(1).transition(Self.fade)
            }
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
        .frame(height: list.isEmpty ? 0 : RegisterMetrics.notifierBarHeight, alignment: .top)
        .clipped()
        .animation(.motion(RegisterEffects.notifierResize), value: list.isEmpty)
    }
}

/// A small capsule: one symbol, the message and its link as a button; a click anywhere on it acts too.
struct NotifierView: View {
    let notifier: RegisterNotifier
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.symbolName(notifier.kind))
                .foregroundStyle(Self.tint(notifier.kind))
                .accessibilityHidden(true)
            if !notifier.text.isEmpty {
                Text(verbatim: notifier.text).lineLimit(1).truncationMode(.tail)
            }
            if let link = notifier.link {
                Button(link, action: action)
                    .buttonStyle(.link)
                    .fixedSize()
            }
        }
        .font(ThemeFont.body.font)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Self.tint(notifier.kind).opacity(0.14)))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
    }

    static func symbolName(_ kind: RegisterNotifier.Kind) -> String {
        kind == .undo ? "arrow.uturn.backward" : StatusSymbol.warning
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
