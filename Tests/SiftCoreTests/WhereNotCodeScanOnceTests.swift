//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// One `where --refs` answer scans the tree for the `not code` mentions of a name once, whichever of its parts asks.
@Suite(.temporaryDirectories)
struct WhereNotCodeScanOnceTests {
    private static func renderer(over root: URL) throws -> WhereRenderer {
        var renderer = try WhereRenderer(store: TestSources.makeStore())
        renderer.readsWorkingTree(under: root, enumerator: FileEnumerator(repoRoot: root, config: SiftConfig()), bounds: TextSearchFiles.Bounds())
        return renderer
    }

    /// A second ask for the same name is served from the first scan, so a catalog gone from the disk is still listed; a different name scans afresh.
    @Test
    func aSecondAskForTheSameNameIsServedFromTheFirstScan() throws {
        let root = try TemporaryDirectory.make("scan-once")
        try TestSources.write("{\n\"strings\" : {\n\"Gizmo\" : { }\n}\n}\n", to: "Resources/Walk.xcstrings", in: root)
        let nonCodeMentions = try #require(Self.renderer(over: root).nonCodeMentions)

        let first = nonCodeMentions("Gizmo")
        try FileManager.default.removeItem(at: root.appendingPathComponent("Resources/Walk.xcstrings"))
        let second = nonCodeMentions("Gizmo")
        let other = nonCodeMentions("Widget")

        #expect(first.files.map(\.path) == ["Resources/Walk.xcstrings"])
        #expect(second.files.map(\.path) == ["Resources/Walk.xcstrings"])
        #expect(other.files.isEmpty)
        #expect(other.catalogsRead == 0)
    }
}
