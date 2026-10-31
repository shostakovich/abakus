import AppKit
import SwiftUI

/// A help popover never has the focus, so it watches events for Escape and clicks outside.
struct CalloutDismissal: ViewModifier {
    enum Response: Equatable {
        case ignore, dismiss, dismissAndConsume
    }

    static let escapeKeyCode: UInt16 = 53

    let closesOnClickOutside: Bool
    let dismiss: () -> Void
    @State private var monitor: Any?
    @State private var isHovered = false

    static func response(to event: NSEvent, isHovered: Bool, closesOnClickOutside: Bool) -> Response {
        switch event.type {
        case .keyDown: event.keyCode == escapeKeyCode ? .dismissAndConsume : .ignore
        case .leftMouseDown, .rightMouseDown: closesOnClickOutside && !isHovered ? .dismiss : .ignore
        default: .ignore
        }
    }

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            let response = MainActor.assumeIsolated {
                let response = Self.response(
                    to: event, isHovered: isHovered, closesOnClickOutside: closesOnClickOutside)
                if response != .ignore { dismiss() }
                return response
            }
            return response == .dismissAndConsume ? nil : event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
