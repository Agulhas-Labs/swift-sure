//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// In a repository with no Swift file the hook answers nothing and writes nothing.
///
/// The install is machine-wide, so the hook runs in projects that hold no Swift: a denial would be an outline of a document no index is wanted for, and answering builds `.swift-sure/` and an exclude line in a repository that never asked for either.
@Suite(.temporaryDirectories)
struct SwiftFreeRepositoryTests {
    private static func repository(withSwift: Bool) throws -> URL {
        let root = try TemporaryDirectory.make("swift-free").appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notes = (1 ... 800).map { "Line \($0) of the notes" }.joined(separator: "\n")
        try ("# Notes\n\n## Part\n\n" + notes + "\n").write(to: root.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        if withSwift {
            try "struct Alpha {}\n".write(to: root.appendingPathComponent("Alpha.swift"), atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-b", "main"], ["add", "-A"], ["commit", "-m", "seed"]] {
            try MCPTestRepo.run(git: arguments, in: root)
        }
        return root.resolvingSymlinksInPath()
    }

    private static func lookup(_ payload: [String: Any], command: String? = nil, in root: URL) throws -> PreToolUseCommand.Lookup? {
        try PreToolUseCommand.lookup(
            command: command,
            payload: payload,
            in: root.path,
            noting: SuppressionLog(fileURL: TemporaryDirectory.make("ignored").appendingPathComponent("ignored.jsonl")),
            couldAnswer: { _, _ in true }
        )
    }

    private static func read(_ root: URL) -> [String: Any] {
        ["tool_name": "Read", "tool_input": ["file_path": root.appendingPathComponent("notes.md").path]]
    }

    private static var grep: [String: Any] {
        ["tool_name": "Grep", "tool_input": ["pattern": "DepotStore"]]
    }

    private static func writesNothing(in root: URL, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".swift-sure").path), sourceLocation: sourceLocation)
        let exclude = (try? String(contentsOf: root.appendingPathComponent(".git/info/exclude"), encoding: .utf8)) ?? ""
        #expect(!exclude.contains(".swift-sure"), sourceLocation: sourceLocation)
    }

    @Test
    func aWholeReadOfADocumentIsLeftAloneWhereTheRepositoryHoldsNoSwift() throws {
        let root = try Self.repository(withSwift: false)

        #expect(try Self.lookup(Self.read(root), in: root) == nil)
        Self.writesNothing(in: root)
    }

    @Test
    func aSearchIsLeftAloneWhereTheRepositoryHoldsNoSwift() throws {
        let root = try Self.repository(withSwift: false)

        #expect(try Self.lookup(Self.grep, in: root) == nil)
        #expect(try Self.lookup([:], command: "grep -rn DepotStore .", in: root) == nil)
        Self.writesNothing(in: root)
    }

    @Test
    func aToolchainRunIsGivenNoAdviceWhereTheRepositoryHoldsNoSwift() throws {
        let root = try Self.repository(withSwift: false)

        #expect(try Self.lookup([:], command: "swift test", in: root) == nil)
        Self.writesNothing(in: root)
    }

    /// The control: the same document read in a repository with one Swift file is still answered.
    @Test
    func theSameReadIsStillAnsweredWhereTheRepositoryHoldsSwift() throws {
        let root = try Self.repository(withSwift: true)

        #expect(try Self.lookup(Self.read(root), in: root)?.inPlace != nil)
        #expect(try Self.lookup([:], command: "swift test", in: root) != nil)
    }

    /// A walk cut short at its limit has not shown there is no Swift, so it reads as Swift present.
    @Test
    func aWalkThatStopsAtItsLimitCountsAsSwiftPresent() throws {
        let root = try TemporaryDirectory.make("swift-free-large").appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(SwiftTree.holdsNoSwift(inRepositoryOf: root.path))
        for index in 0 ..< SwiftTree.visitLimit + 1 {
            try Data().write(to: root.appendingPathComponent("f\(index).txt"))
        }
        #expect(!SwiftTree.holdsNoSwift(inRepositoryOf: root.path))
    }
}
