#if os(iOS)
    import SwiftUI
    import UIKit

    extension View {
        /// True while the on-screen keyboard shows; a hardware keyboard's slim shortcut bar does not count.
        func tracksSoftwareKeyboard(_ isShown: Binding<Bool>) -> some View {
            modifier(SoftwareKeyboardTracker(isShown: isShown))
        }
    }

    private struct SoftwareKeyboardTracker: ViewModifier {
        private static let minimumHeight: CGFloat = 120

        @Binding var isShown: Bool

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
                    isShown = Self.coveredHeight($0) > Self.minimumHeight
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    isShown = false
                }
        }

        private static func coveredHeight(_ notification: Notification) -> CGFloat {
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return 0
            }
            guard let screen = notification.object as? UIScreen else { return frame.height }
            return screen.bounds.intersection(frame).height
        }
    }
#endif
