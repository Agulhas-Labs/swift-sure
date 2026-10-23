//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// A run's ledger record keeps the argv as the caller asked for it, so what `swift-sure run` adds itself never reads as a narrowing.
@Suite(.temporaryDirectories)
struct RunRecordsAskedArgvTests {
    @Test
    func aCoverageRunOfSwiftTestRecordsTheArgvAsAsked() throws {
        let command = try RunCommand.parse(["--coverage", "--", "swift", "test"])

        let record = Self.record(of: command)

        #expect(record.arguments == ["swift", "test"])
        #expect(RunNarrowing.isUnnarrowed(record.arguments))
        #expect(command.arguments.contains("--enable-code-coverage"))
    }

    @Test
    func anXcodebuildRunRecordsTheArgvAsAskedAndItsSuggestionKeepsTheScheme() async throws {
        let command = try RunCommand.parse(["--coverage", "--", "xcodebuild", "-scheme", "Gizmo", "test"])
        let record = Self.record(of: command)
        let directory = try TemporaryDirectory.make("records-asked-argv")
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = RunLedger(fileURL: directory.appendingPathComponent(RunLedger.fileName))
        ledger.record(record)
        let toolchain = ToolchainIdentity(description: record.toolchain)

        let check = CheckupTestRuns(ledger: ledger, tree: Self.tree, toolchain: toolchain, packageRoots: ["."], swiftPMRoots: [], checkout: "/repo", now: Date().addingTimeInterval(2 * RunLedger.trustWindow), environment: [:])
        let (findings, _) = try await check.evaluate { (tests: 1, runners: .both) }

        #expect(record.arguments == ["xcodebuild", "-scheme", "Gizmo", "test"])
        #expect(command.arguments.contains("-collect-test-diagnostics"))
        #expect(RunNarrowing.isUnnarrowed(record.arguments))
        #expect(findings.first?.command == "\(ProductName.current.binary) run -- xcodebuild -scheme Gizmo test")
    }

    /// Records already written with SwiftSure's own additions in their argv read as the whole suite.
    @Test(arguments: [
        ["swift", "test", "--enable-code-coverage"],
        ["xcodebuild", "-scheme", "Gizmo", "test", "-collect-test-diagnostics", "never"],
        ["xcodebuild", "-scheme", "Gizmo", "-enableCodeCoverage", "YES", "test"],
    ])
    func siftsOwnAdditionsAreNeutral(arguments: [String]) {
        #expect(RunNarrowing.isUnnarrowed(arguments))
    }

    @Test(arguments: [
        ["xcodebuild", "-scheme", "Gizmo", "test", "-collect-test-diagnostics", "on-failure"],
        ["xcodebuild", "-scheme", "Gizmo", "test", "-enableCodeCoverage", "NO"],
    ])
    func otherValuesOfThoseOptionsStillNarrow(arguments: [String]) {
        #expect(!RunNarrowing.isUnnarrowed(arguments))
    }
}

private extension RunRecordsAskedArgvTests {
    static var tree: TreeKey {
        TreeKey(value: "4f2a9c1e0000000000000000000000000000abcd")
    }

    static func record(of command: RunCommand) -> RunLedger.Record {
        let root = URL(fileURLWithPath: "/repo")
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 0, report: nil, log: nil, repositoryRoot: root)
        return command.ledgerRecord(outcome, ran: RunCommand.ProvableRun(tree: tree, workingDirectory: "."), in: root, toolchain: "Apple Swift version 6.4", milliseconds: 1)
    }
}
