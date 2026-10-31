import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct EditorPopupClickTests {
    @Test func aClickOutsideTheListAndItsFieldClosesItAndGoesOn() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let model = fixture.model()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        #expect(editor.dropDown != nil)
        let field = CGRect(x: 300, y: 100, width: 150, height: 24)
        let areas = EditorPopupsLayer.keepOpenAreas(
            editor: editor, anchors: [.main(.category): field], size: CGSize(width: 900, height: 600))
        #expect(!EditorPopupsLayer.closesPopups(at: CGPoint(x: 310, y: 110), keeping: areas))
        #expect(!EditorPopupsLayer.closesPopups(at: CGPoint(x: 310, y: 140), keeping: areas))
        #expect(EditorPopupsLayer.closesPopups(at: CGPoint(x: 850, y: 590), keeping: areas))
    }
}
