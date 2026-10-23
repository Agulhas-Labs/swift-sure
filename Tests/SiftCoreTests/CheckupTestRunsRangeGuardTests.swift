//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A red recorded on the working tree is read for the working tree, and never for a range ending at another revision.
@Suite(.serialized)
struct CheckupTestRunsRangeGuardTests {
    @Test
    func aRangeEndingElsewhereReadsNoRecordedRun() async throws {
        try await TemporaryDirectory.withScope {
            let repo = try TestSources.makeTempRepo()
            try TestSources.write("struct Gizmo {}\n", to: "Sources/Gizmo.swift", in: repo)
            try TestSources.commitAll(in: repo, message: "seed")
            try TestSources.write("struct Gizmo { var spin = 1 }\n", to: "Sources/Gizmo.swift", in: repo)
            let tree = try #require(TreeKey.of(repositoryRoot: repo))
            RunLedger.inRepository(at: repo).recordFailure(RunLedger.Record(tree: tree.value, command: "swift test", toolchain: "any", finishedAt: Date(), log: nil, milliseconds: 1, arguments: ["swift", "test"], exitCode: 1, stoppedBySift: false))
            let git = GitContext(repoRoot: repo)
            let freshness = Freshness(tree: WorkingTree(repository: "gizmo"), headShort: "0000000", dirtyCount: 1, parseErrorFiles: 0)

            let workingTree = try await CheckupFrame(git: git, range: DiffRange.resolve(nil, git: git, command: "checkup")).answer(freshness: freshness, offset: 0)
            let atHead = try await CheckupFrame(git: git, range: DiffRange.resolve("HEAD", git: git, command: "checkup")).answer(freshness: freshness, offset: 0)

            #expect(workingTree.contains("\nfailed     swift test failed"))
            #expect(!atHead.contains("\nfailed "))
            #expect(atHead.contains("test runs (1 uncommitted change; a run records the working tree's content)"))
        }
    }

    @Test
    func aRangeEndingAtAnotherRevisionKeepsTheRevisionReason() async throws {
        try await TemporaryDirectory.withScope {
            let repo = try TestSources.makeTempRepo()
            for body in ["1", "2", "3"] {
                try TestSources.write("struct Gizmo { var spin = \(body) }\n", to: "Sources/Gizmo.swift", in: repo)
                try TestSources.commitAll(in: repo, message: "seed \(body)")
            }
            try TestSources.write("struct Gizmo { var spin = 4 }\n", to: "Sources/Gizmo.swift", in: repo)
            let git = GitContext(repoRoot: repo)
            let freshness = Freshness(tree: WorkingTree(repository: "gizmo"), headShort: "0000000", dirtyCount: 1, parseErrorFiles: 0)

            let earlier = try await CheckupFrame(git: git, range: DiffRange.resolve("HEAD~2...HEAD~1", git: git, command: "checkup")).answer(freshness: freshness, offset: 0)

            #expect(earlier.contains("test runs (a run records the working tree's content, and this range ends at"))
        }
    }
}
