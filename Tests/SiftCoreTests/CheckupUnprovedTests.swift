//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// When `checkup` says a package root is `unproved`, what it names as not counting, and the command it suggests.
@Suite(.serialized)
struct CheckupUnprovedTests {
    private typealias Fixture = CheckupFailedRunTests

    @Test
    func aGreenProvedWouldNotTrustDoesNotProveAndGivesItsReason() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            ledger.record(Fixture.record(["swift", "test"], ago: 60, workingDirectory: "Packages/Gizmo"))

            let (findings, _) = try await Fixture.check(ledger, roots: ["."])

            #expect(findings.map(\.findingClass) == [.unproved])
            let text = findings.first?.text ?? ""
            #expect(text.hasPrefix("no unnarrowed test run is proved green on this content (not counting: swift test: no green run of swift test is recorded for this tree's content from the repository root; one is recorded only from Packages/Gizmo)"))
            #expect(text.hasSuffix("; 12 tests reach the change"))
        }
    }

    @Test
    func anExpiredGreenDoesNotProve() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            ledger.record(Fixture.record(["swift", "test"], ago: RunLedger.trustWindow + 120))

            let (findings, _) = try await Fixture.check(ledger, roots: ["."])

            #expect(findings.first?.text.contains("swift test: the green run recorded for this tree is 62m old") == true)
        }
    }

    @Test
    func aNarrowedGreenDoesNotProveAndIsNamed() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            ledger.record(Fixture.record(["swift", "test", "--filter", "GizmoTests"], ago: 240))

            let (findings, _) = try await Fixture.check(ledger, roots: ["."])

            #expect(findings.map(\.findingClass) == [.unproved])
            #expect(findings.first?.text.contains("(not counting: swift test --filter, narrowed, 4m ago)") == true)
            #expect(findings.first?.command == "\(ProductName.current.binary) run -- swift test")
        }
    }

    @Test
    func theSuggestionIsTheNewestUnnarrowedCommandShellQuoted() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            var older = Fixture.record(["swift", "test"], ago: 600)
            older = RunLedger.Record(tree: "0000", command: older.command, toolchain: older.toolchain, finishedAt: older.finishedAt, log: nil, milliseconds: 1, workingDirectory: ".", arguments: older.arguments)
            let newer = RunLedger.Record(tree: "1111", command: "swift test --scratch-path", toolchain: older.toolchain, finishedAt: Fixture.now.addingTimeInterval(-300), log: nil, milliseconds: 1, workingDirectory: ".", arguments: ["swift", "test", "--scratch-path", "Gizmo Build"])
            ledger.record(older)
            ledger.record(newer)
            ledger.record(Fixture.record(["swift", "test", "--filter", "GizmoTests"], ago: 60))

            let (findings, _) = try await Fixture.check(ledger, roots: ["."])

            #expect(findings.first?.command == "\(ProductName.current.binary) run -- swift test --scratch-path 'Gizmo Build'")
        }
    }

    @Test
    func aProvedRootHasNoLineAndNamesItsProof() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            ledger.record(Fixture.record(["swift", "test", "-c", "debug"], ago: 120))

            let (findings, status) = try await Fixture.check(ledger, roots: ["."])

            #expect(findings.isEmpty)
            #expect(status == .checked(basis: "swift test -c debug proved green on this content 2m ago", bound: nil))
        }
    }

    @Test
    func theLedgerSwitchedOffIsNotChecked() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Fixture.ledger()
            let check = CheckupTestRuns(ledger: ledger, tree: Fixture.tree, toolchain: Fixture.toolchain, packageRoots: ["."], swiftPMRoots: [], checkout: "/repo", now: Fixture.now, environment: [RunLedger.switchName: "0"])

            let (findings, status) = try await check.evaluate { nil }

            #expect(findings.isEmpty)
            #expect(status == .notChecked(reason: "the run ledger switched off (\(RunLedger.switchName)=0)"))
        }
    }
}
