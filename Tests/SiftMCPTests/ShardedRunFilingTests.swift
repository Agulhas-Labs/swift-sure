//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A sharded `swift-sure test` files itself in the run log with the failing tests, tree and invocation a wrapped run files, so `flakes` counts it.
@Suite(.temporaryDirectories)
struct ShardedRunFilingTests {
    private static let red = TestRunResult(answer: "✘ 1 failed", exitCode: 1, reconciled: TestRunResult.Reconciled(isGreen: false, stoppedBySift: false), runToken: "1a2b3c4d", shards: 3, failedTests: ["Gizmo/aTest()"])

    /// The one line a run wrote to a log, run in a repository that holds a package manifest.
    private func filedLine(of result: TestRunResult, arguments: [String], sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String: Any] {
        let repository = try TemporaryDirectory.make("sharded-filing-repository")
        let scratch = try TemporaryDirectory.make("sharded-filing-scratch")
        defer {
            try? FileManager.default.removeItem(at: repository)
            try? FileManager.default.removeItem(at: scratch)
        }
        // A tree has a hash only once there is a HEAD to hash it against.
        for arguments in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--allow-empty", "-q", "-m", "x"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = repository
            process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, sourceLocation: sourceLocation)
        }
        try "// swift-tools-version: 6.0\n".write(to: repository.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        var command = try TestCommand.parse([])
        command.startingDirectory = repository
        command.environment = [:]
        command.output = RecordedOutput().output
        command.givenArguments = arguments
        let file = scratch.appendingPathComponent("run.jsonl")
        command.usageLog = RunUsageLog(fileURL: file)
        command.runPackage = { _ in result }
        try? await command.run()
        let text = try String(contentsOf: file, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first, sourceLocation: sourceLocation)
        return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], sourceLocation: sourceLocation)
    }

    @Test func aRedShardedRunFilesItsFailingTestsTreeAndInvocation() async throws {
        let entry = try await filedLine(of: Self.red, arguments: ["--shards", "3"])

        #expect(entry["kind"] as? String == "sift test")
        #expect(entry["failed"] as? [String] == ["Gizmo/aTest()"])
        #expect(entry["failed_total"] as? Int == 1)
        #expect(entry["tree"] is String)
        #expect(entry["invocation"] is String)
    }

    @Test func theInvocationTellsTwoCommandLinesApart() async throws {
        let three = try await filedLine(of: Self.red, arguments: ["--shards", "3"])
        let two = try await filedLine(of: Self.red, arguments: ["--shards", "2", "--filter", "X"])

        #expect(three["invocation"] as? String != two["invocation"] as? String)
    }

    @Test func aRunThatCannotSayWhatFailedFilesNoFailedKey() async throws {
        let entry = try await filedLine(of: TestRunResult(answer: "✘ build failed", exitCode: 1), arguments: [])

        #expect(entry["failed"] == nil)
        #expect(entry["failed_total"] == nil)
        #expect(entry["tree"] is String)
    }

    /// `flakes` counts a test filed by a sharded run, where it had counted the run as unrecorded.
    @Test func flakesCountsATestAShardedRunFiled() throws {
        let file = try TemporaryDirectory.make("sharded-filing-flakes").appendingPathComponent("flakes.jsonl")
        let failing = #"{"kind":"sift test","exit":1,"ms":100,"ts":"2026-08-21T10:00:00Z","root":"/repo/a","failed":["Gizmo/Depot/restock()"],"failed_total":1,"tree":"t1","invocation":"all"}"#
        let passing = #"{"kind":"sift test","exit":0,"ms":100,"ts":"2026-08-20T10:00:00Z","root":"/repo/a","failed":[],"failed_total":0,"tree":"t1","invocation":"all"}"#
        try ([failing, passing].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let rendered = RunFailureHistoryReport.render(fileURL: file, root: nil, redactor: nil, query: "restock")

        #expect(rendered.contains("1 test recorded failing"), "\(rendered)")
        #expect(rendered.contains("sift test — failed 1 of 2 runs"), "\(rendered)")
    }
}
