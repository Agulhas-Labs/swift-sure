//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A digest target at a revision is spelled against the revision's own paths, never against what the working tree's filesystem has become since.
@Suite(.temporaryDirectories)
struct RevisionTargetIgnoresWorkingTreeTests {
    private static func head(of root: URL) throws -> String {
        try TestSources.runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A directory the revision holds is a symbolic link to another directory today, and the revision's file is still the one read.
    @Test
    func aDirectoryThatIsALinkTodayStillNamesTheRevisionsOwnFile() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Anchor {}\n", to: "Sources/Alias/Thing.swift", in: root)
        try TestSources.write("public struct Rival {}\n", to: "Sources/Real/Thing.swift", in: root)
        try TestSources.commitAll(in: root, message: "alias and real")
        let head = try Self.head(of: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Alias"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Sources/Alias").path, withDestinationPath: "Real")
        let engine = try SiftEngine(directory: root)

        let digest = try engine.digest(targets: ["Sources/Alias/Thing.swift"], at: head, options: DigestOptions())

        #expect(digest.contains("struct Anchor"), "\(digest)")
        #expect(!digest.contains("Rival"), "\(digest)")
    }

    /// A directory the revision spells in lower case, renamed in the working tree, is refused as the module's directory under the revision's spelling.
    @Test
    func aDirectoryRenamedByCaseSinceIsRefusedUnderTheRevisionsSpelling() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Helper {}\n", to: "Sources/gizmo/Helper.swift", in: root)
        try TestSources.commitAll(in: root, message: "lower case")
        let head = try Self.head(of: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/gizmo"))
        try TestSources.write("public struct Helper {}\n", to: "Sources/Gizmo/Helper.swift", in: root)
        let engine = try SiftEngine(directory: root)

        let error = #expect(throws: EngineError.self) {
            try engine.digest(targets: ["Sources/gizmo"], at: head, options: DigestOptions())
        }

        #expect(error?.description.contains("`Sources/gizmo` is a module's directory") == true, "\(String(describing: error))")
        #expect(error?.description.contains("Sources/Gizmo") == false, "\(String(describing: error))")
    }
}
