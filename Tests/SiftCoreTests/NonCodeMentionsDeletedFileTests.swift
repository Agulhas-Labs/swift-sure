//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A file listed for the `not code` scan that the tree no longer holds, as git still lists a file deleted without staging: it is not read, so it is not counted as read, and its name is not a mention.
@Suite(.temporaryDirectories)
struct NonCodeMentionsDeletedFileTests {
    @Test
    func aListedFileTheTreeNoLongerHoldsIsNeitherCountedNorNamed() throws {
        let root = try TemporaryDirectory.make("noncode-deleted")
        try TestSources.write("struct Kept {}\n", to: "Sources/Kept.swift", in: root)
        try TestSources.write("# Notes\n", to: "Docs/Notes.md", in: root)

        let found = NonCodeMentions.scan(
            name: "Gizmo",
            swiftFiles: ["Sources/Gizmo.swift", "Sources/Kept.swift"],
            markdownFiles: ["Docs/Gizmo.md", "Docs/Notes.md"],
            catalogFiles: ["Resources/Gizmo.xcstrings"],
            under: root
        )

        #expect(found.swiftFilesRead == 1)
        #expect(found.markdownFilesRead == 1)
        #expect(found.fileNames.isEmpty)
    }
}
