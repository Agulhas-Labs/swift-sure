//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A directory holding only part of one module is served as that module's digest over just its files.
@Suite(.temporaryDirectories)
struct DigestFolderSliceTests {
    private static func render(_ target: String, withSoloType: Bool = false) throws -> String {
        let store = try TestSources.makeStore()
        let root = try TestSources.makeTempDirectory()
        let files = try [
            TestSources.parsed("public struct Lonely {}\n", path: "Sources/Solo/Lonely.swift", in: root),
            TestSources.parsed("public struct Middle {}\n", path: "Sources/Solo/Session/Middle.swift", in: root),
            TestSources.parsed("public struct Deep {}\n", path: "Sources/Solo/Session/Store/Deep.swift", in: root),
            TestSources.parsed("public struct Helper {}\n", path: "Sources/Gizmo/Helper.swift", in: root),
        ] + (withSoloType ? [TestSources.parsed("public struct Solo {}\n", path: "Sources/Solo/Solo.swift", in: root)] : [])
        try store.replaceFiles(files) { file in
            (file.split(separator: "/").dropFirst().first.map(String.init) ?? "", false)
        }
        let renderer = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: root)
        return try renderer.render(target: target, options: DigestOptions())
    }

    @Test
    func aWholeModuleDirectoryKeepsTheModuleHeader() throws {
        let output = try Self.render("Sources/Gizmo")

        #expect(output.contains("module Gizmo — 1 top-level declarations"))
        #expect(!output.contains("folder "))
        #expect(try output == Self.render("Gizmo/"))
    }

    @Test
    func aFolderTwoLevelsDeepServesOnlyItsOwnFiles() throws {
        let output = try Self.render("Sources/Solo/Session/Store")

        #expect(output.contains("folder Store in module Solo — 1 top-level declarations"))
        #expect(output.contains("Deep"))
        #expect(!output.contains("Middle"))
        #expect(!output.contains("Lonely"))
    }

    @Test
    func aFolderCoversItsSubfoldersToo() throws {
        let output = try Self.render("Sources/Solo/Session/")

        #expect(output.contains("folder Session in module Solo — 2 top-level declarations"))
        #expect(output.contains("Middle"))
        #expect(output.contains("Deep"))
        #expect(!output.contains("Lonely"))
    }

    @Test
    func aFolderSliceOmitsTheModuleShadowNoteTheModuleDirectoryCarries() throws {
        let slice = try Self.render("Sources/Solo/Session", withSoloType: true)
        let module = try Self.render("Sources/Solo", withSoloType: true)

        #expect(slice.contains("folder Session in module Solo"))
        #expect(!slice.contains("also exists"))
        #expect(module.contains("also exists"))
    }

    @Test
    func aFolderAtARevisionIsRefusedAsAFolderInItsModule() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("public struct Lonely {}\n", to: "Sources/Solo/Lonely.swift", in: root)
        try TestSources.write("public struct Deep {}\n", to: "Sources/Solo/Sub/Deep.swift", in: root)
        try TestSources.commitAll(in: root, message: "modules")
        let head = try TestSources.runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let engine = try SiftEngine(directory: root)

        let error = #expect(throws: EngineError.self) {
            try engine.digest(targets: ["Sources/Solo/Sub"], at: head, options: DigestOptions())
        }

        #expect(error?.description.contains("`Sources/Solo/Sub` is a folder in module Sources") == true, "\(String(describing: error))")
    }
}
