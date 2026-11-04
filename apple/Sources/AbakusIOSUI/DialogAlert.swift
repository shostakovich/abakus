#if os(iOS)
    import AbakusUI
    import SwiftUI

    /// Shows the topmost dialog of the stack as an alert; answering it brings up the next.
    struct DialogAlert: ViewModifier {
        let dialogs: [PresentedDialog]

        func body(content: Content) -> some View {
            let top = dialogs.last
            content.alert(
                top.map { TouchDialog($0.dialog).title } ?? "",
                isPresented: Binding(get: { top != nil }, set: { _ in }),
                presenting: top
            ) { presented in
                ForEach(Array(TouchDialog(presented.dialog).answers.enumerated()), id: \.offset) { _, answer in
                    Button(answer.title, role: answer.isCancel ? .cancel : nil) {
                        presented.answer(answer.choice, isChecked: answer.isChecked)
                    }
                }
            } message: { presented in
                Text(TouchDialog(presented.dialog).message)
            }
        }
    }
#endif
