import SwiftUI

extension View {
    package func toolTip(_ text: String?) -> some View {
        help(text ?? "")
    }
}
