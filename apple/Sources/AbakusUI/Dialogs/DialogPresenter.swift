import Foundation

@MainActor
protocol DialogPresentation: AnyObject {
    func show(
        _ dialog: TaskDialog<AnyDialogChoice>, id: UUID,
        onAnswer: @escaping @MainActor (AnyDialogChoice, Bool) -> Void)
    func close(_ id: UUID)
}

/// Keeps the presented sheets in step with the dialog stack: the stack stays the model, the sheets follow it.
@MainActor
final class DialogPresenter {
    private struct Shown {
        let id: UUID
        let dialog: TaskDialog<AnyDialogChoice>
    }

    private let presentation: any DialogPresentation
    private var shown: [Shown] = []

    init(presentation: any DialogPresentation) {
        self.presentation = presentation
    }

    func update(_ dialogs: [PresentedDialog]) {
        let kept = zip(shown, dialogs).prefix { $0.id == $1.id && $0.dialog == $1.dialog }.count
        for stale in shown[kept...].reversed() {
            presentation.close(stale.id)
        }
        shown.removeSubrange(kept...)
        for entry in dialogs[kept...] {
            shown.append(Shown(id: entry.id, dialog: entry.dialog))
            presentation.show(entry.dialog, id: entry.id) { [weak self] choice, isChecked in
                self?.shown.removeAll { $0.id == entry.id }
                entry.answer(choice, isChecked: isChecked)
            }
        }
    }
}
