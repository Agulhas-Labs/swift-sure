//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A module's directory at a revision is refused whichever way the caller spells it.
@Suite(.temporaryDirectories)
struct RevisionModuleDirectorySpellingTests {
    private static func refusal(of target: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String? {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Helper {}\n", to: "Sources/Gizmo/Helper.swift", in: root)
        try TestSources.commitAll(in: root, message: "modules")
        let head = try TestSources.runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let engine = try SiftEngine(directory: root)
        let error = #expect(throws: EngineError.self, sourceLocation: sourceLocation) {
            try engine.digest(targets: [target], at: head, options: DigestOptions())
        }
        return error?.description
    }

    @Test
    func aDotSlashSpellingIsRefusedAsTheModulesDirectory() throws {
        let message = try Self.refusal(of: "./Sources/Gizmo")

        #expect(message?.contains("`Sources/Gizmo` is a module's directory") == true, "\(String(describing: message))")
    }

    @Test
    func aWrongCaseSpellingIsRefusedAsTheModulesDirectory() throws {
        let message = try Self.refusal(of: "sources/gizmo")

        #expect(message?.contains("`Sources/Gizmo` is a module's directory") == true, "\(String(describing: message))")
    }
}
