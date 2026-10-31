import AppKit
import SwiftUI

/// Presents the given dialogs as sheets of the window this view lives in.
struct DialogHost: NSViewRepresentable {
    let dialogs: [PresentedDialog]

    func makeNSView(context: Context) -> HostView { HostView() }

    func updateNSView(_ view: HostView, context: Context) {
        view.dialogs = dialogs
    }

    final class HostView: NSView {
        private lazy var presenter = DialogPresenter(
            presentation: SheetDialogPresentation { [weak self] in self?.window })

        var dialogs: [PresentedDialog] = [] {
            didSet { present() }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            present()
        }

        private func present() {
            guard window != nil else { return }
            presenter.update(dialogs)
        }
    }
}
