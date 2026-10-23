//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The crashed process's own trap is quoted ahead of `File.swift:N: Fatal error: …` text a passing process merely printed.
struct RunTestCrashCrashedProcessTrapTests {
    private static var signalLine: String {
        "error: Process '/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path /Users/dev/Pallet/.build/out/Products/Debug/PalletTests.xctest --testing-library swift-testing' exited with unexpected signal code 5"
    }

    private static var fake: String {
        "Shelf/Rack.swift:9: Fatal error: printed by a passing test"
    }

    private static var real: String {
        "Pallet/Pallet.swift:7: Fatal error: Unexpectedly found nil while unwrapping an Optional value"
    }

    /// A passing process prints a look-alike, then the crashed process starts `topples()` and traps: the crashed process's trap is first.
    @Test
    func theCrashedProcessTrapLeadsAPassingProcessLookalike() {
        let report = Self.report([
            Self.signalLine,
            "Test Suite 'All tests' started at 2000-01-01 12:00:00.000.",
            "Test Case '-[PalletTests.PalletTests testStacks]' started.",
            Self.fake,
            "Test Case '-[PalletTests.PalletTests testStacks]' passed (0.000 seconds).",
            "Test Suite 'All tests' passed at 2000-01-01 12:00:00.001.",
            "◇ Test run started.",
            "◇ Test topples() started.",
            Self.real,
        ])

        #expect(report.testCrash?.traps.first == Self.real)
    }

    /// The crashed process traps before any test of its own started, so nothing places the trap in a test: its trap still leads the passing process's look-alike.
    @Test
    func aCrashBeforeAnyTestStartedStillLeadsWithItsOwnTrap() {
        let report = Self.report([
            Self.signalLine,
            "Test Suite 'All tests' started at 2000-01-01 12:00:00.000.",
            Self.fake,
            "Test Suite 'All tests' passed at 2000-01-01 12:00:00.001.",
            "◇ Test run started.",
            Self.real,
        ])

        #expect(report.testCrash?.traps.first == Self.real)
    }

    private static func report(_ lines: [String]) -> RunReport {
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        for line in lines {
            filter.consume(line: line)
        }
        return filter.finish(exitCode: 1)
    }
}
