//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// A run's ledger record keeps the argv as the caller asked for it, so what `swift-sure run` adds itself never reads as a narrowing.
struct RunRecordsAskedArgvTests {
    @Test
    func aCoverageRunOfSwiftTestRecordsTheArgvAsAsked() throws {
        let command = try RunCommand.parse(["--coverage", "--", "swift", "test"])

        let record = Self.record(of: command)

        #expect(record.arguments == ["swift", "test"])
        #expect(command.arguments.contains("--enable-code-coverage"))
    }

    @Test
    func anXcodebuildRunRecordsTheArgvAsAsked() throws {
        let command = try RunCommand.parse(["--coverage", "--", "xcodebuild", "-scheme", "Gizmo", "test"])

        let record = Self.record(of: command)

        #expect(record.arguments == ["xcodebuild", "-scheme", "Gizmo", "test"])
        #expect(command.arguments.contains("-collect-test-diagnostics"))
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
