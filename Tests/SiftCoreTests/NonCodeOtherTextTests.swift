//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The other tracked text a rename must change (a build manifest, a script) listed under `not code`: found by one `git grep`, never in a binary or gitignored file, never for a lowercase name.
@Suite(.temporaryDirectories)
struct NonCodeOtherTextTests {
    private static func makeRepo() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Gizmo {}\nfunc gizmo() {}\n", to: "Sources/App/Gizmo.swift", in: root)
        try TestSources.write("project(App)\nadd_library(App Gizmo.cpp)\ntarget_link_libraries(App Gizmo)\n", to: "targets.cmake", in: root)
        try TestSources.write("#!/bin/sh\necho start\necho Gizmo\necho gizmo\n", to: "Scripts/build.sh", in: root)
        try TestSources.write("ignored/\n", to: ".gitignore", in: root)
        try TestSources.write("Gizmo\n", to: "ignored/notes.txt", in: root)
        try Data([0x47, 0x69, 0x7A, 0x6D, 0x6F, 0x00, 0x01, 0x02]).write(to: root.appendingPathComponent("Resources.bin"))
        try TestSources.commitAll(in: root, message: "seed")
        return root
    }

    private static func answer(_ root: URL, symbol: String, options: WhereOptions) async throws -> String {
        let engine = try SiftEngine(directory: root)
        TestSources.raiseOpenBudgetForAColdStore(engine)
        let freshness = try await engine.ensureFresh()
        return try await engine.lookup(symbol: symbol, freshness: freshness, options: options)
    }

    @Test
    func aBuildManifestAndAScriptNamingTheNameAreListedWithTheirLines() async throws {
        let root = try Self.makeRepo()
        let output = try await Self.answer(root, symbol: "Gizmo", options: WhereOptions(includeReferences: true))
        let files = try await Self.answer(root, symbol: "Gizmo", options: WhereOptions(filesOnly: true))

        #expect(output.contains("3 other-text lines"), "\(output)")
        #expect(output.contains("  targets.cmake (2): 2, 3"), "\(output)")
        #expect(output.contains("  Scripts/build.sh (1): 3"), "\(output)")
        #expect(files.contains("targets.cmake (not code 2)"), "\(files)")
        #expect(files.contains("Scripts/build.sh"), "\(files)")
    }

    @Test
    func aBinaryFileAndAGitignoredFileAreNotListed() async throws {
        let root = try Self.makeRepo()
        let output = try await Self.answer(root, symbol: "Gizmo", options: WhereOptions(includeReferences: true))

        #expect(!output.contains("Resources.bin"), "\(output)")
        #expect(!output.contains("ignored/notes.txt"), "\(output)")
    }

    @Test
    func aLowercaseNameSweepsNoOtherText() async throws {
        let root = try Self.makeRepo()
        let output = try await Self.answer(root, symbol: "gizmo", options: WhereOptions(includeReferences: true))

        #expect(!output.contains("Scripts/build.sh"), "\(output)")
        #expect(!output.contains("other-text line"), "\(output)")
    }

    @Test
    func theNoneLineNamesOtherTrackedTextAsReadOrNot() throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Gadget {}\n", to: "Sources/App/Gadget.swift", in: root)
        let swift = ["Sources/App/Gadget.swift"]
        let read = NonCodeMentions.scan(name: "Gizmo", swiftFiles: swift, markdownFiles: [], otherText: [:], under: root)
        let unread = NonCodeMentions.scan(name: "Gizmo", swiftFiles: swift, markdownFiles: [], under: root)

        #expect(WhereNonCodeSection(mentions: read, isAmbiguous: false).noneLine.contains("nor in any other tracked text file; binary files and untracked ignored files not read"))
        #expect(WhereNonCodeSection(mentions: unread, isAmbiguous: false).noneLine.hasSuffix("; other text files not read"))
    }

    @Test
    func aPathHoldingANewlineAndOneInASubdirectoryListUnderTheirTruePaths() {
        let output = Data("new\nline.txt\u{0}3\u{0}Gizmo here\nScripts/build.sh\u{0}7\u{0}echo Gizmo\nplain.txt\u{0}1\u{0}Gizmo\n".utf8)

        let lines = GitContext.otherTextLines(parsing: output)

        #expect(lines == ["new\nline.txt": [3], "Scripts/build.sh": [7], "plain.txt": [1]], "\(lines)")
    }
}
