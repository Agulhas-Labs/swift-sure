//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// Covers the `filtered:` line counting suites an earlier green filtered run of the same tree passed through `RunCommand` and the ledger it writes.
@Suite(.temporaryDirectories)
struct RunFilteredReachEarlierRunTests {
    static var source: String {
        """
        import XCTest

        struct Pallet {}

        final class PalletTests: XCTestCase {
            func testA() {
                _ = Pallet()
            }
        }

        final class GadgetTests: XCTestCase {
            func testB() {
                _ = Pallet()
            }
        }
        """
    }

    static func dirty(_ repository: URL) throws {
        let file = repository.appendingPathComponent("Tests/GizmoTests/PalletTests.swift")
        try (source + "\nextension Pallet {\n    var size: Int { 1 }\n}\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// A transcript with the closing suite lines a proof needs, which ``RunInventoryNoteTests/ended(_:)`` leaves out.
    static func green(_ method: String) -> [String] {
        let tally = "\t Executed 1 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds"
        let name = "-[GizmoTests.\(method == "testA" ? "PalletTests" : "GadgetTests") \(method)]"
        return [
            "Test Suite 'Selected tests' started at 2000-01-01 12:00:00.346.",
            "Test Case '\(name)' started.",
            "Test Case '\(name)' passed (0.000 seconds).",
            "Test Suite 'Selected tests' passed at 2000-01-01 12:00:00.347.",
            tally,
        ]
    }

    /// A transcript whose one test failed, so the run's answer is the filtered summary and not the raw log.
    static func red(_ method: String) -> [String] {
        let name = "-[GizmoTests.GadgetTests \(method)]"
        return [
            "Test Suite 'Selected tests' started at 2000-01-01 12:00:00.346.",
            "Test Case '\(name)' started.",
            "/tmp/gizmo/Tests/GizmoTests/GadgetTests.swift:14: error: \(name) : XCTAssertEqual failed: (\"1\") is not equal to (\"2\")",
            "Test Case '\(name)' failed (0.000 seconds).",
            "Test Suite 'Selected tests' failed at 2000-01-01 12:00:00.347.",
            "\t Executed 1 tests, with 1 failures (0 unexpected) in 0.001 (0.001) seconds",
        ]
    }

    static func note(_ printed: String) -> [String] {
        printed.split(separator: "\n").map(String.init).filter { $0.hasPrefix("  filtered:") }
    }

    @Test
    func aSecondGreenFilteredRunDoesNotNameTheSuiteTheFirstPassed() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        try Self.dirty(repository)
        let (first, _) = try await RunInventoryNoteTests.run(in: repository, printing: Self.green("testA"), exiting: 0, extraArguments: ["--filter", "PalletTests"])
        let (second, _) = try await RunInventoryNoteTests.run(in: repository, printing: Self.green("testB"), exiting: 0, extraArguments: ["--filter", "GadgetTests"])

        #expect(Self.note(first.printed).first?.contains("run swift test --filter GizmoTests.GadgetTests") == true, "\(first.printed)")
        #expect(Self.note(second.printed) == ["  filtered: every suite reaching the change has passed on this tree (this run and 1 earlier run)"], "\(second.printed)")
    }

    @Test
    func aRedFirstRunCountsForNothing() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        try Self.dirty(repository)
        _ = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testA"]), exiting: 1, extraArguments: ["--filter", "PalletTests"])
        let (second, _) = try await RunInventoryNoteTests.run(in: repository, printing: Self.green("testB"), exiting: 0, extraArguments: ["--filter", "GadgetTests"])

        #expect(Self.note(second.printed).first?.contains("run swift test --filter GizmoTests.PalletTests") == true, "\(second.printed)")
    }

    @Test
    func aRedSecondRunIsNeverToldEverySuiteHasPassedNorSentBackToTheFirst() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        try Self.dirty(repository)
        _ = try await RunInventoryNoteTests.run(in: repository, printing: Self.green("testA"), exiting: 0, extraArguments: ["--filter", "PalletTests"])
        let (second, _) = try await RunInventoryNoteTests.run(in: repository, printing: Self.red("testB"), exiting: 1, extraArguments: ["--filter", "GadgetTests"])

        #expect(second.printed.contains("failed"), "\(second.printed)")
        #expect(Self.note(second.printed).isEmpty, "\(second.printed)")
        #expect(!second.printed.contains("PalletTests"), "\(second.printed)")
    }
}
