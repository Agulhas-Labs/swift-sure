//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// A package-mode `swift-sure test` files what `swift-sure run -- swift test` files for the tree it ran on, so `run --proved -- swift test` stands on it.
@Suite(.temporaryDirectories)
struct TestCommandShardedProofTests {
    private static let green = TestRunResult(answer: "✔ 3 passed", exitCode: 0, reconciled: TestRunResult.Reconciled(isGreen: true, stoppedBySift: false), runToken: "1a2b3c4d", shards: 3)
    private static let red = TestRunResult(answer: "✘ 1 failed", exitCode: 1, reconciled: TestRunResult.Reconciled(isGreen: false, stoppedBySift: false))

    /// A green reconciliation on an unmoved tree records the green `run --proved -- swift test` asks the ledger for, in the package's directory and as an unnarrowed run.
    @Test
    func aGreenPackageRunOnAnUnmovedTreeProvesTheTreeForSwiftTest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.run(Self.green)
        let tree = try #require(TreeKey.of(repositoryRoot: fixture.repository))
        let toolchain = try #require(ToolchainIdentity.current())
        let trust = RunLedger.inRepository(at: fixture.repository)
            .trust(tree: tree, command: ProofKey.command(of: ["swift", "test"]), toolchain: toolchain, workingDirectory: ".", environment: [:])
        guard case let .proved(record) = trust else {
            Issue.record("not proved: \(trust)")
            return
        }

        #expect(record.arguments == ["swift", "test"])
        #expect(record.log == nil)
        #expect(record.runToken == "1a2b3c4d")
        #expect(record.shards == 3)
    }

    /// A red sharded run files the token and shard count its logs carry, so a refusal can name them.
    @Test
    func aRedShardedRunIsFiledWithItsTokenAndShardCount() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await #expect(throws: ExitCode(1)) {
            try await fixture.run(TestRunResult(answer: "✘ 1 failed", exitCode: 1, reconciled: TestRunResult.Reconciled(isGreen: false, stoppedBySift: false), runToken: "1a2b3c4d", shards: 3))
        }

        let red = try #require(RunLedger.inRepository(at: fixture.repository).failedRuns.records().first)

        #expect(red.runToken == "1a2b3c4d")
        #expect(red.shards == 3)
    }

    /// A tree edited while the shards ran records nothing: the suite read neither tree whole.
    @Test
    func aTreeThatMovedDuringTheRunRecordsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.run(Self.green, whileRunning: { try? "// edited\n".write(to: $0.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8) })

        #expect(RunLedger.inRepository(at: fixture.repository).records().isEmpty)
        #expect(RunLedger.inRepository(at: fixture.repository).failedRuns.records().isEmpty)
    }

    /// A red reconciliation after a green of the same tree revokes the proof, as a red `swift-sure run` does.
    @Test
    func aRedReconciliationAfterAGreenOfTheSameTreeRefusesTheProof() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.run(Self.green)
        // The ledger keeps whole seconds, and a red dated to the green's own second refuses the green too.
        try await Task.sleep(for: .seconds(1.1))
        await #expect(throws: ExitCode(1)) { try await fixture.run(Self.red) }
        let ledger = RunLedger.inRepository(at: fixture.repository)
        #expect(ledger.records().isEmpty)
        let red = try #require(ledger.failedRuns.records().first)
        #expect(red.exitCode == 1)
        #expect(red.stoppedBySift == false)
        let tree = try #require(TreeKey.of(repositoryRoot: fixture.repository))
        let toolchain = try #require(ToolchainIdentity.current())
        let trust = ledger.trust(tree: tree, command: ProofKey.command(of: ["swift", "test"]), toolchain: toolchain, workingDirectory: ".", environment: [:])
        #expect(trust != .notProved(.noRecord))
        if case .proved = trust {
            Issue.record("a red run left the tree proved")
        }
    }

    /// A build that failed, or a listing that named nothing, never reached the shards and records neither a proof nor a failure.
    @Test
    func aRunThatNeverReachedTheShardsRecordsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await #expect(throws: ExitCode(1)) { try await fixture.run(TestRunResult(answer: "✘ build failed", exitCode: 1)) }

        #expect(RunLedger.inRepository(at: fixture.repository).records().isEmpty)
        #expect(RunLedger.inRepository(at: fixture.repository).failedRuns.records().isEmpty)
    }

    /// A red on a tree edited while the shards ran records nothing: it is not known to be the tree the run began on.
    @Test
    func aRedOnATreeThatMovedDuringTheRunRecordsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await #expect(throws: ExitCode(1)) {
            try await fixture.run(Self.red, whileRunning: { try? "// edited\n".write(to: $0.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8) })
        }

        #expect(RunLedger.inRepository(at: fixture.repository).records().isEmpty)
        #expect(RunLedger.inRepository(at: fixture.repository).failedRuns.records().isEmpty)
    }

    /// A run from a package below the repository root files its record under that directory, as `swift-sure run` spells it, so `run --proved` from there finds it.
    @Test
    func aRunFromANestedPackageRecordsItsRelativeDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let nested = fixture.repository.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0\n".write(to: nested.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try await fixture.run(Self.green, startingDirectory: nested)

        let records = RunLedger.inRepository(at: fixture.repository).records()

        #expect(records.map(\.workingDirectory) == ["Sub"])
    }

    /// A red is filed whatever the ledger switch says, since it only ever revokes a proof.
    @Test
    func aRedWithTheLedgerSwitchedOffIsStillFiled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        await #expect(throws: ExitCode(1)) { try await fixture.run(Self.red, environment: [EnvironmentVariable.runLedger.name: "0"]) }

        #expect(RunLedger.inRepository(at: fixture.repository).records().isEmpty)
        #expect(RunLedger.inRepository(at: fixture.repository).failedRuns.records().count == 1)
    }

    /// With the ledger switched off a green records nothing.
    @Test
    func aGreenWithTheLedgerSwitchedOffRecordsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.run(Self.green, environment: [EnvironmentVariable.runLedger.name: "0"])

        #expect(RunLedger.inRepository(at: fixture.repository).records().isEmpty)
    }
}

private extension TestCommandShardedProofTests {
    /// A git repository holding a package manifest, which `swift-sure test` treats as a package run.
    struct Fixture {
        let repository: URL
        private let scratch: URL

        init() throws {
            repository = try TemporaryDirectory.make("sharded-proof-repository")
            scratch = try TemporaryDirectory.make("sharded-proof-scratch")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["init", "-q"]
            process.currentDirectoryURL = repository
            process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0)
            try "// swift-tools-version: 6.0\n".write(to: repository.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: repository)
            try? FileManager.default.removeItem(at: scratch)
        }

        /// `swift-sure test` in the package, whose shards `result` stands for; `whileRunning` is what happens to the repository meanwhile.
        func run(_ result: TestRunResult, environment: [String: String] = [:], startingDirectory: URL? = nil, whileRunning: (@Sendable (URL) -> Void)? = nil) async throws {
            var command = try TestCommand.parse([])
            command.startingDirectory = startingDirectory ?? repository
            command.environment = environment
            command.output = RecordedOutput().output
            command.usageLog = RunUsageLog(fileURL: scratch.appendingPathComponent("run.jsonl"))
            let repository = repository
            command.runPackage = { _ in
                whileRunning?(repository)
                return result
            }
            try await command.run()
        }
    }
}
