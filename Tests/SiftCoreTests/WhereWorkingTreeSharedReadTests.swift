//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The conformers block's file accounting and the `not code` section read each Swift file once between them.
@Suite(.temporaryDirectories)
struct WhereWorkingTreeSharedReadTests {
    /// A Swift file the accounting's search read is not read again by the `not code` scan of the same name, so a file gone from the disk between the two is still listed.
    @Test
    func theNotCodeScanTakesASwiftFileFromTheSearchsRead() throws {
        let root = try TemporaryDirectory.make("shared-read")
        try TestSources.write("/// A Gizmo.\nstruct Other {}\n", to: "Sources/Walk.swift", in: root)
        var enumerator = FileEnumerator(repoRoot: root, config: SiftConfig())
        enumerator.gitListing = { ["Sources/Walk.swift"] }
        var renderer = try WhereRenderer(store: TestSources.makeStore())
        renderer.readsWorkingTree(under: root, enumerator: enumerator, bounds: TextSearchFiles.Bounds())
        let search = try #require(renderer.textSearchFiles)
        let nonCodeMentions = try #require(renderer.nonCodeMentions)

        #expect(search("Gizmo") != nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Walk.swift"))
        let mentions = nonCodeMentions("Gizmo")

        #expect(mentions.files.map(\.path) == ["Sources/Walk.swift"])
    }
}
