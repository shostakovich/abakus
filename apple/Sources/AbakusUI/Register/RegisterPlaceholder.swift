import SwiftUI

public struct RegisterPlaceholder: View {
    let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(ThemeFont.headline.font)
            .foregroundStyle(ThemeColor.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
