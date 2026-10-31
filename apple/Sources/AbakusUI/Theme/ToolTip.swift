import SwiftUI

extension View {
    func toolTip(_ text: String?) -> some View {
        help(text ?? "")
    }
}
