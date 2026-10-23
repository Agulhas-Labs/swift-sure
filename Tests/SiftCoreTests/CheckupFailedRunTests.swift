//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Which recorded reds `checkup` calls `failed`, and which it names on the `test runs` basis instead.
@Suite(.serialized)
struct CheckupFailedRunTests {
    static let toolchain = ToolchainIdentity(description: "Apple Swift version 6.4 · Target: arm64-apple-macosx26.0")
    static let tree = TreeKey(value: "4f2a9c1e0000000000000000000000000000abcd")
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func record(_ arguments: [String], ago seconds: TimeInterval, workingDirectory: String = ".", exitCode: Int32? = nil, stopped: Bool? = nil, log: String? = "gizmo.log") -> RunLedger.Record {
        RunLedger.Record(tree: tree.value, command: ProofKey.command(of: arguments), toolchain: toolchain.description, finishedAt: now.addingTimeInterval(-seconds), log: log, milliseconds: 1000, checkout: "/repo", workingDirectory: workingDirectory, arguments: arguments, exitCode: exitCode, stoppedBySift: stopped)
    }

    static func check(_ ledger: RunLedger, roots: [String] = []) async throws -> (findings: [CheckupFinding], status: CheckupStatus) {
        try await CheckupTestRuns(ledger: ledger, tree: tree, toolchain: toolchain, packageRoots: roots, swiftPMRoots: Set(roots), checkout: "/repo", now: now, environment: [:])
            .evaluate { (tests: 12, runners: .both) }
    }

    static func ledger() throws -> RunLedger {
        try RunLedger(fileURL: TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName))
    }

    @Test(arguments: [(Int32(0), "exit 0 refused as a proof"), (Int32(4), "exit 4, no test matched"), (Int32(6), "exit 6, an unclean inventory")])
    func aRedSiftDeclaredIsNamedOnTheBasis(exitCode: Int32, reason: String) async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test", "--filter", "GizmoTests"], ago: 120, exitCode: exitCode, stopped: false))

            let (findings, status) = try await Self.check(ledger)

            #expect(findings.isEmpty)
            guard case let .checked(basis, _) = status else {
                Issue.record("not checked: \(status)")
                return
            }
            #expect(basis?.contains("swift test --filter GizmoTests: \(reason)") == true)
        }
    }

    @Test
    func aRedSiftStoppedIsNotAFailure() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test"], ago: 120, exitCode: 1, stopped: true))

            let (findings, status) = try await Self.check(ledger)

            #expect(findings.isEmpty)
            #expect(status == .checked(basis: "recorded; swift test: stopped by \(ProductName.current.binary), 2m ago", bound: nil))
        }
    }

    @Test
    func aRedWithNoExitCodeIsFailedAndSaysSo() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test"], ago: 120))

            let (findings, _) = try await Self.check(ledger)

            #expect(findings.map(\.findingClass) == [.failed])
            #expect(findings.first?.text == "swift test failed 2m ago (exit not recorded; log .swift-sure/runs/gizmo.log)")
            #expect(findings.first?.command == "\(ProductName.current.binary) run -- swift test")
        }
    }

    @Test
    func aGreenFromAnotherDirectoryDoesNotClearARed() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test"], ago: 300, exitCode: 1, stopped: false))
            ledger.record(Self.record(["swift", "test"], ago: 60, workingDirectory: "Packages/Gizmo"))

            let (findings, _) = try await Self.check(ledger)

            #expect(findings.map(\.text) == ["swift test failed 5m ago (exit 1; log .swift-sure/runs/gizmo.log)"])
        }
    }

    @Test
    func aRedOlderThanTheTrustWindowIsNotRead() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test"], ago: RunLedger.trustWindow + 60, exitCode: 1, stopped: false))

            let (findings, status) = try await Self.check(ledger)

            #expect(findings.isEmpty)
            #expect(status == .notChecked(reason: "no run recorded on this content"))
        }
    }

    @Test
    func aNarrowedGreenDoesNotClearAnOlderUnnarrowedRed() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test"], ago: 300, exitCode: 1, stopped: false))
            ledger.record(Self.record(["swift", "test", "--filter", "GizmoTests"], ago: 60))

            let (findings, _) = try await Self.check(ledger, roots: ["."])

            #expect(findings.map(\.findingClass) == [.failed, .unproved])
            #expect(findings.last?.text.contains("swift test --filter, narrowed, 60s ago") == true)
        }
    }

    @Test
    func anUnnarrowedGreenAfterARedClearsIt() async throws {
        try await TemporaryDirectory.withScope {
            let ledger = try Self.ledger()
            ledger.recordFailure(Self.record(["swift", "test", "--filter", "GizmoTests"], ago: 300, exitCode: 1, stopped: false))
            ledger.record(Self.record(["swift", "test", "--parallel"], ago: 60))

            let (findings, status) = try await Self.check(ledger, roots: ["."])

            #expect(findings.isEmpty)
            #expect(status == .checked(basis: "swift test --parallel proved green on this content 60s ago", bound: nil))
        }
    }
}
