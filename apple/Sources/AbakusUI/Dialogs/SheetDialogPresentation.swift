import AppKit
import SwiftUI

/// Shows each dialog as a sheet on the window's topmost sheet, so it covers the form that asked it.
@MainActor
final class SheetDialogPresentation: DialogPresentation {
    private struct Presented {
        let sheet: NSWindow
        var escapeMonitor: Any?
    }

    private let window: () -> NSWindow?
    private var presented: [UUID: Presented] = [:]

    init(window: @escaping () -> NSWindow?) {
        self.window = window
    }

    func show(
        _ dialog: TaskDialog<AnyDialogChoice>, id: UUID,
        onAnswer: @escaping @MainActor (AnyDialogChoice, Bool) -> Void
    ) {
        guard let parent = window()?.topmostSheet else { return }
        if dialog.commandLinks.isEmpty {
            showAlert(DialogAlert(dialog), id: id, on: parent, onAnswer: onAnswer)
        } else {
            showCommandLinks(dialog, id: id, on: parent, onAnswer: onAnswer)
        }
    }

    func close(_ id: UUID) {
        guard let entry = presented.removeValue(forKey: id) else { return }
        if let monitor = entry.escapeMonitor { NSEvent.removeMonitor(monitor) }
        entry.sheet.sheetParent?.endSheet(entry.sheet)
    }

    private func showAlert(
        _ alert: DialogAlert, id: UUID, on parent: NSWindow,
        onAnswer: @escaping @MainActor (AnyDialogChoice, Bool) -> Void
    ) {
        let sheet = alert.alert.window
        var entry = Presented(sheet: sheet)
        if alert.escapesWithoutButton {
            entry.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.window === sheet, event.keyCode == CalloutDismissal.escapeKeyCode else { return event }
                MainActor.assumeIsolated { sheet.sheetParent?.endSheet(sheet, returnCode: .cancel) }
                return nil
            }
        }
        presented[id] = entry
        alert.alert.beginSheetModal(for: parent) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, let entry = self.presented.removeValue(forKey: id) else { return }
                if let monitor = entry.escapeMonitor { NSEvent.removeMonitor(monitor) }
                onAnswer(alert.choice(for: response), alert.isSuppressed)
            }
        }
    }

    private func showCommandLinks(
        _ dialog: TaskDialog<AnyDialogChoice>, id: UUID, on parent: NSWindow,
        onAnswer: @escaping @MainActor (AnyDialogChoice, Bool) -> Void
    ) {
        let host = NSHostingController(
            rootView: CommandLinkSheet(dialog: dialog) { [weak self] choice, isChecked in
                guard let self, let entry = presented.removeValue(forKey: id) else { return }
                parent.endSheet(entry.sheet)
                onAnswer(choice, isChecked)
            })
        host.sizingOptions = .preferredContentSize
        let sheet = NSWindow(contentViewController: host)
        presented[id] = Presented(sheet: sheet)
        parent.beginSheet(sheet)
    }
}

extension NSWindow {
    var topmostSheet: NSWindow { attachedSheet?.topmostSheet ?? self }
}
