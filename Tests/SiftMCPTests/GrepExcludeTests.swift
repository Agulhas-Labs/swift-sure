//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A recursive `grep` narrowed by `--exclude-dir=<name>` or `--exclude=*.<ext>` is read as the same sweep without those files; every other spelling of either flag leaves the command unread.
@Suite(.temporaryDirectories)
struct GrepExcludeTests {
    private static func directory(_ files: [String: String]) throws -> URL {
        let root = try TemporaryDirectory.make("grepexclude").appendingPathComponent("grepexclude")
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static func tree() throws -> URL {
        try directory([
            "Sources/A.swift": "let Name = 1\n",
            "Sources/X/.build/C.swift": "let Name = 3\n",
            ".build/checkouts/B.swift": "let Name = 2\n",
            "Docs/n.md": "Name\n",
        ])
    }

    /// The last path component of each file whose lines the search printed, sorted.
    private static func printedFiles(_ arguments: [String], in root: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let search = try #require(ShellGrep(arguments: arguments), sourceLocation: sourceLocation)
        guard case let .printed(lines) = search.run(in: root.path) else {
            Issue.record("\(arguments) did not print", sourceLocation: sourceLocation)
            return []
        }
        return Set(lines.map { ($0.file as NSString).lastPathComponent }).sorted()
    }

    @Test
    func anExcludedDirectoryIsLeftOutAtAnyDepth() throws {
        let root = try Self.tree()

        #expect(try Self.printedFiles(["-rn", "Name", ".", "--exclude-dir=.build"], in: root) == ["A.swift", "n.md"])
        #expect(try Self.printedFiles(["-rn", "--exclude-dir", ".build", "Name", "."], in: root) == ["A.swift", "n.md"])
        #expect(try Self.printedFiles(["-rn", "Name", ".", "--exclude-dir=.build", "--exclude=*.md"], in: root) == ["A.swift"])
        #expect(try Self.printedFiles(["-rn", "Name", "."], in: root).count == 4)
    }

    @Test
    func theNoBinaryFlagChangesNothingOnATextTree() throws {
        let root = try Self.tree()
        let plain = try Self.printedFiles(["-rn", "Name", ".", "--exclude-dir=.build", "--exclude-dir=.git"], in: root)

        #expect(try Self.printedFiles(["-rIn", "Name", ".", "--exclude-dir=.build", "--exclude-dir=.git"], in: root) == plain)
        #expect(!plain.isEmpty)
    }

    @Test(arguments: ["--exclude-dir=Sources/X", "--exclude-dir=*.build", "--exclude-dir={.git,.build}", "--exclude-dir=..", "--exclude-dir=.", "--exclude-dir=", "--exclude=*.swift", "--exclude=foo*", "--exclude=*.{md,txt}", "--exclude=*.m?"])
    func anyOtherSpellingLeavesTheCommandUnread(_ flag: String) {
        #expect(ShellGrep(arguments: ["-rn", "Name", ".", flag]) == nil)
    }

    @Test
    func anExclusionThatMeetsAnOperandOutrightOrNoRecursionLeavesTheCommandUnread() {
        #expect(ShellGrep(arguments: ["-rn", "Name", ".build", "--exclude-dir=.build"]) == nil)
        #expect(ShellGrep(arguments: ["-n", "Name", "Sources/A.swift", "--exclude-dir=.build"]) == nil)
        #expect(ShellGrep(arguments: ["-rn", "Name", "Sources", "--exclude-dir=.build"]) != nil)
    }

    @Test
    func excludesArePartOfWhatTheSearchIs() throws {
        let root = try Self.tree()
        let bare = try #require(ShellGrep(arguments: ["-rn", "Name", "."]))
        let narrowed = try #require(ShellGrep(arguments: ["-rn", "Name", ".", "--exclude-dir=.build"]))

        #expect(bare != narrowed)
        #expect(bare.run(in: root.path) != narrowed.run(in: root.path))
    }

    @Test
    func aNarrowedSweepIsJudgedAsTheSameSweepWithoutThoseFiles() async throws {
        let root = try MCPTestRepo.make(declaring: "Alpha")
        let uses = (1 ... 28).map { "func gadget\($0)() -> Gadget { Gadget() }" }.joined(separator: "\n")
        try MCPTestRepo.add([
            "Package.swift": "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.target(name: \"App\")])\n",
            "Sources/App/Parts/Gadget.swift": "public struct Gadget {\n    public init() {}\n}\n\(uses)\n",
        ], to: root)
        try MCPTestRepo.build(root)
        try await SiftEngine(directory: root).ensureFresh()

        let bare = try await InPlaceAnswerTests.outcome("grep -rn Gadget Sources/App/Parts | head -1", in: root)
        let narrowed = try await InPlaceAnswerTests.outcome("grep -rn Gadget Sources/App/Parts --exclude-dir=.build | head -1", in: root)

        #expect(bare == .withheld(.notSmaller))
        #expect(narrowed == bare)
    }
}
