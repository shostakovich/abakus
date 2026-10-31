import AppKit
import Testing

@testable import AbakusUI

@MainActor
@Suite struct MainWindowTests {
    @Test func minimumContentKeepsTheMinimumWindowFrame() {
        let content = NSRect(origin: .zero, size: MainWindowMetrics.minimumContentSize)
        let frame = NSWindow.frameRect(forContentRect: content, styleMask: MainWindowMetrics.styleMask)
        #expect(frame.size == CGSize(width: 800, height: 550))
    }
}
