//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// An answer the hook serves from a file the version control is told not to report is the corrected text, and its header names the file it reparsed, as the plain digest's does.
@Suite(.temporaryDirectories)
struct InPlaceReparsedHeaderTests {
    private static var path: String {
        "Sources/App/Depot.swift"
    }

    private static var named: String {
        "reparsed from the live file: \(path)"
    }

    /// The fixture: `Depot` indexed at its commit, then `old` replaced by `new` behind the version control's back.
    ///
    /// `Alpha` is edited before the commit, so the index rewrites its rows after `Depot`'s whichever file the first build stored last: `Depot`'s rows are then not the store's newest, and rows written again for it are numbered afresh rather than given back the numbers they had.
    private static func editedRepository(replacing old: String, with new: String) async throws -> URL {
        let root = try await InPlaceAnswerTests.indexedRepository()
        let alpha = root.appendingPathComponent("Sources/App/Alpha.swift")
        try String(contentsOf: alpha, encoding: .utf8).replacingOccurrences(of: "func go() {}", with: "func go() {}\n    func stop() {}")
            .write(to: alpha, atomically: true, encoding: .utf8)
        try MCPTestRepo.run(git: ["add", "-A"], in: root)
        try MCPTestRepo.run(git: ["commit", "-m", "depot", "--no-gpg-sign"], in: root)
        try MCPTestRepo.run(git: ["update-index", "--assume-unchanged", path], in: root)
        // Indexed at the new head before the edit, so the edit is the only thing the index has not seen.
        try await SiftEngine(directory: root).ensureFresh()
        let file = root.appendingPathComponent(path)
        try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: old, with: new)
            .write(to: file, atomically: true, encoding: .utf8)
        return root
    }

    @Test
    func aFileDigestNamesTheFileItReparsed() async throws {
        let root = try await Self.editedRepository(replacing: "stock1()", with: "stock41()")

        let answered = try #require(try await InPlaceAnswerTests.answered("cat \(Self.path)", in: root))

        #expect(answered.reason.contains("func stock41()"), "\(answered.reason)")
        #expect(answered.reason.contains(Self.named), "\(answered.reason)")
    }

    @Test
    func aMemberAnswerNamesTheFileItReparsed() async throws {
        let root = try await Self.editedRepository(replacing: "let count = 1\n", with: "let count = 9\n")

        let answered = try #require(try await InPlaceAnswerTests.answered("grep -n 'func stock1' \(Self.path)", in: root))

        #expect(answered.reason.contains("let count = 9"), "\(answered.reason)")
        #expect(answered.reason.contains(Self.named), "\(answered.reason)")
    }

    @Test
    func aMemberRangeNamesTheFileItReparsed() async throws {
        let root = try await Self.editedRepository(replacing: "let count = 1\n", with: "let count = 9\n")

        let answered = try #require(try await InPlaceAnswerTests.answered("sed -n '/func stock1()/,/^    }/p' \(Self.path)", in: root))

        #expect(answered.reason.contains("let count = 9"), "\(answered.reason)")
        #expect(answered.reason.contains(Self.named), "\(answered.reason)")
    }
}
