//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// The two walks over a tree keep their own rules: the source probe skips the trees no lookup is aimed at, and the Swift-free proof skips only what the indexer skips and the compiled bundles beside it.
@Suite(.temporaryDirectories)
struct SwiftTreeWalkRuleTests {
    /// A tree holding `count` empty files under each of `bulky`, and each of `files` with its text.
    private static func tree(named name: String, bulky: [String], count: Int, files: [String: String]) throws -> URL {
        let root = try TemporaryDirectory.make(name).appendingPathComponent("tree").resolvingSymlinksInPath()
        for directory in bulky {
            let headers = root.appendingPathComponent(directory)
            try FileManager.default.createDirectory(at: headers, withIntermediateDirectories: true)
            for index in 0 ..< count {
                FileManager.default.createFile(atPath: headers.appendingPathComponent("H\(index).h").path, contents: nil)
            }
        }
        for (path, text) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return root
    }

    /// Each bulky tree alone outruns the visit limit, so the source probe finds `Foo.swift` only by skipping all of them, wherever the filesystem lists them.
    @Test
    func theSourceProbeSkipsVendoredAndPackageTreesOnItsWayToSwift() throws {
        let root = try Self.tree(
            named: "walk-probe",
            bulky: ["vendor/Headers", "Kit.bundle/Headers", "App.swiftpm/Headers", "Kit.swiftpm/Headers"],
            count: SwiftTree.visitLimit + 100,
            files: ["Src/Foo.swift": "struct Foo {}\n"]
        )

        #expect(SwiftTree.holdsSource(at: ".", relativeTo: root.path))
    }

    @Test
    func theSwiftFreeProofSkipsACompiledBundleButNotADirectoryMerelyNamedLikeOne() throws {
        let headers = try Self.tree(named: "walk-bundles", bulky: ["Frameworks/Big.framework/Headers"], count: SwiftTree.visitLimit + 100, files: ["notes.md": "# Notes\n"])
        let sources = try Self.tree(named: "walk-sources", bulky: [], count: 0, files: ["Docs.bundled/V.swift": "struct V {}\n"])

        #expect(SwiftTree.holdsNoSwift(inRepositoryOf: headers.path))
        #expect(!SwiftTree.holdsNoSwift(inRepositoryOf: sources.path))
    }
}
