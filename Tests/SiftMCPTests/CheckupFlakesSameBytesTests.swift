//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Pins that `checkup`'s flaky check reads only `flakes`' same-tree tier: a test both failing and passing on identical bytes under one command line.
@Suite(.temporaryDirectories)
struct CheckupFlakesSameBytesTests {
    private static func record(_ failed: [String], tree: String, in root: URL, to file: URL) {
        RunUsageLog(fileURL: file).record(
            logKey: "swift test",
            exitCode: failed.isEmpty ? 0 : 1,
            answer: RunUsageLog.Answer(failedTests: failed),
            repositoryRoot: root,
            milliseconds: 100,
            startedOn: TreeContentHash.RunKey(tree: tree, invocation: "all")
        )
    }

    @Test
    func aTestFailingAndPassingOnIdenticalBytesIsRead() throws {
        let file = try TemporaryDirectory.make("checkup-flakes").appendingPathComponent("run.jsonl")
        let repo = try MCPTestRepo.make()
        Self.record(["spin()"], tree: "aaaa", in: repo, to: file)
        Self.record([], tree: "aaaa", in: repo, to: file)
        let evidence = try #require(CheckupFlakes.evidence(logAt: file, root: repo.path))

        #expect(evidence.runs == 2)
        #expect(evidence.tests == [CheckupFlakeEvidence.Recorded(name: "spin()", failed: 1, runs: 2)])
    }

    @Test
    func aTestFailingOnOneTreeAndPassingOnAnotherIsNotRead() throws {
        let file = try TemporaryDirectory.make("checkup-flakes").appendingPathComponent("run.jsonl")
        let repo = try MCPTestRepo.make()
        Self.record(["spin()"], tree: "aaaa", in: repo, to: file)
        Self.record([], tree: "bbbb", in: repo, to: file)
        let evidence = try #require(CheckupFlakes.evidence(logAt: file, root: repo.path))

        #expect(evidence.runs == 2)
        #expect(evidence.tests.isEmpty)
    }

    @Test
    func aLogWithNoRunInTheRepositoryHasNoEvidence() throws {
        let file = try TemporaryDirectory.make("checkup-flakes").appendingPathComponent("run.jsonl")
        let repo = try MCPTestRepo.make()
        try Self.record(["spin()"], tree: "aaaa", in: MCPTestRepo.make(), to: file)

        #expect(CheckupFlakes.evidence(logAt: file, root: repo.path) == nil)
    }
}
