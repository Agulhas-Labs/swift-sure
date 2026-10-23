//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure checkup`'s `uncovered` check over a real working-tree change and a coverage record written beside it.
@Suite(.temporaryDirectories)
struct CheckupUncoveredCommandTests {
    private static var path: String {
        "Sources/App/Widget.swift"
    }

    private static func answer(in repository: URL, arguments: [String] = [], sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String] {
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (text, refused) = try await CheckupCommand.parse(["--root", repository.path] + arguments).answer(registry: registry)
        #expect(!refused, sourceLocation: sourceLocation)
        return text.split(separator: "\n").map(String.init)
    }

    /// A committed `Widget` whose working-tree edit adds two executable lines, the second of which the record can say never ran.
    private static func repository(sourceLocation: SourceLocation = #_sourceLocation) throws -> (root: URL, tree: TreeKey) {
        let root = try MCPTestRepo.make()
        try MCPTestRepo.add([path: "struct Widget {\n    func wobble() -> Int {\n        1\n    }\n}\n"], to: root)
        try "struct Widget {\n    func wobble() -> Int {\n        let side = 2\n        return side * side\n    }\n}\n".write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        let tree = try #require(TreeKey.of(repositoryRoot: root), sourceLocation: sourceLocation)
        return (root, tree)
    }

    private static func record(_ tree: String, age: TimeInterval = 5) -> CoverageRecord {
        CoverageRecord(tree: tree, command: ["swift", "test"], measured: [path: [3: 2, 4: 0]], unmeasured: [], measuredAt: Date().addingTimeInterval(-age))
    }

    @Test
    func aRecordOnThisTreeWithAnUncoveredChangedLineIsAFinding() async throws {
        let (root, tree) = try Self.repository()
        try Self.record(tree.value).write(in: root)

        let lines = try await Self.answer(in: root)

        #expect(lines.contains("uncovered  changed lines: 2 executable, 1 covered; uncovered: \(Self.path):4"))
        #expect(lines.contains { $0.hasPrefix("checked: ") && $0.contains("changed-line coverage") })
    }

    @Test
    func aRecordForAnotherTreeIsNotUsedAndGivesTheReason() async throws {
        let (root, _) = try Self.repository()
        try Self.record("another-tree").write(in: root)

        let lines = try await Self.answer(in: root)

        #expect(!lines.contains { $0.hasPrefix("uncovered ") })
        #expect(lines.contains { $0.contains("not checked: ") && $0.contains("changed-line coverage (recorded for another change set — \(ProductName.current.binary) run --coverage --from HEAD -- ") })
    }

    /// Pins the end-to-end pointer: with a coverage record whose line ends `+N more`, bare checkup points to `diff --coverage`, which runs (no refusal) and answers with its coverage section, though it does not list the omitted lines.
    @Test
    func theDiffCoveragePointerRunsAsPrinted() async throws {
        let root = try MCPTestRepo.make()
        try MCPTestRepo.add([Self.path: "struct Widget {\n    func wobble() -> Int {\n        1\n    }\n}\n"], to: root)
        let lets = (1 ... 8).map { "        let side\($0) = \($0)\n        // gap\n" }.joined()
        try "struct Widget {\n    func wobble() -> Int {\n\(lets)        return side1\n    }\n}\n".write(to: root.appendingPathComponent(Self.path), atomically: true, encoding: .utf8)
        let tree = try #require(TreeKey.of(repositoryRoot: root))
        let counts = Dictionary(uniqueKeysWithValues: stride(from: 3, through: 17, by: 2).map { ($0, UInt64(0)) })
        try CoverageRecord(tree: tree.value, command: ["swift", "test"], measured: [Self.path: counts], unmeasured: [], measuredAt: Date().addingTimeInterval(-5)).write(in: root)

        let lines = try await Self.answer(in: root)
        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let (diff, refused) = try await DiffCommand.parse(["--root", root.path, "--coverage"]).answer(registry: registry)

        let finding = try #require(lines.first { $0.hasPrefix("uncovered ") })

        #expect(finding.contains(", +3 more"))
        #expect(finding.hasSuffix(" — \(ProductName.current.binary) diff --coverage"))
        #expect(!refused)
        #expect(diff.contains("none of its 8 lines ran"))
    }

    /// Pins that a change in one nested package root suggests `run --root Sub`, and one across two package roots suggests no command.
    @Test
    func aNestedPackageChangeSuggestsRootFlagAndTwoRootsSuggestNoCommand() async throws {
        let root = try MCPTestRepo.make()
        try MCPTestRepo.add(["Sub/Package.swift": "// swift-tools-version: 6.0\n", "Sub/Sources/Kit/Kit.swift": "struct Kit {}\n", "Other/Package.swift": "// swift-tools-version: 6.0\n", "Other/Sources/Bit/Bit.swift": "struct Bit {}\n"], to: root)
        try "struct Kit { var n = 1 }\n".write(to: root.appendingPathComponent("Sub/Sources/Kit/Kit.swift"), atomically: true, encoding: .utf8)

        let one = try await Self.answer(in: root)

        #expect(one.contains { $0.contains("changed-line coverage (none recorded in this checkout — \(ProductName.current.binary) run --root Sub --coverage --from HEAD -- swift test)") })

        try "struct Bit { var n = 1 }\n".write(to: root.appendingPathComponent("Other/Sources/Bit/Bit.swift"), atomically: true, encoding: .utf8)

        let two = try await Self.answer(in: root)

        #expect(two.contains { $0.contains("changed-line coverage (none recorded in this checkout)") })
    }

    @Test
    func aRecordPastTheTrustWindowIsNotUsed() async throws {
        let (root, tree) = try Self.repository()
        try Self.record(tree.value, age: RunLedger.trustWindow + 600).write(in: root)

        let lines = try await Self.answer(in: root)

        #expect(!lines.contains { $0.hasPrefix("uncovered ") })
        // The age is read when the answer runs, a minute or more after the record on a loaded machine, so the reason is pinned, not the minute count.
        #expect(lines.contains { $0.contains("changed-line coverage (recorded ") && $0.contains("m ago, past the trust window") })
    }

    @Test
    func noRecordIsNotChecked() async throws {
        let (root, _) = try Self.repository()

        let lines = try await Self.answer(in: root)

        #expect(lines.contains { $0.contains("changed-line coverage (none recorded in this checkout — ") })
    }

    @Test
    func aRangeEndingAtAnotherRevisionPutsItOnNotChecked() async throws {
        let (root, tree) = try Self.repository()
        try Self.record(tree.value).write(in: root)
        try MCPTestRepo.run(git: ["add", "-A"], in: root)
        try MCPTestRepo.run(git: ["commit", "-m", "edit"], in: root)
        try MCPTestRepo.run(git: ["tag", "mark"], in: root)
        try "// moved on\n".write(to: root.appendingPathComponent("Sources/App/Later.swift"), atomically: true, encoding: .utf8)
        try MCPTestRepo.run(git: ["add", "-A"], in: root)
        try MCPTestRepo.run(git: ["commit", "-m", "later"], in: root)

        let lines = try await Self.answer(in: root, arguments: ["HEAD~2..mark"])

        #expect(!lines.contains { $0.hasPrefix("uncovered ") })
        #expect(lines.contains { $0.contains("changed-line coverage (a run records the working tree's content, and this range ends at mark)") })
    }
}
