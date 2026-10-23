//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// What a run held to `--require-inventory` leaves behind, and the combinations the flag refuses.
@Suite(.temporaryDirectories)
struct RunRequireInventoryRecordTests {
    private static let flags = ["--require-inventory"]
    private static let lostOne = RunInventoryNoteTests.ended(["testOne", "testTwo"])

    /// The failed-run transcripts kept in `repository`'s run log.
    private static func failedLogs(in repository: URL) -> [String] {
        let runs = SiftPaths.cache(in: repository).appendingPathComponent(RunLog.runsDirectoryName, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: runs.path)) ?? []
        return names.filter { $0.hasPrefix(RunLog.KeptPool.failed.rawValue) && $0.hasSuffix(".log") }.sorted()
    }

    /// Keeps the cache the run writes under `repository` out of its tree, so the tree a run starts on is the tree it ends on.
    private static func ignoreCache(in repository: URL) throws {
        try ".swift-sure/\n.build/\n".write(to: repository.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    }

    /// A run turned into a 6 is a failure: its log joins the kept failed ones, and an earlier failure of the same command is not cleared as if the command had passed.
    @Test
    func anExitSixKeepsItsLogAsAFailureAndClearsNoEarlierOne() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let bin = try TemporaryDirectory.make("run-require-inventory-bin")
        defer { try? FileManager.default.removeItem(at: bin) }
        _ = try await RunInventoryNoteTests.run(in: repository, printing: Self.lostOne, exiting: 1, flags: Self.flags, bin: bin)
        #expect(Self.failedLogs(in: repository).count == 1)

        let (_, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: Self.lostOne, exiting: 0, flags: Self.flags, bin: bin)

        #expect(thrown == ExitCode(6))
        #expect(Self.failedLogs(in: repository).count == 2)
    }

    /// An exit-6 run is not a proof of its tree, though the command exited 0; the same run without the flag is.
    @Test
    func anExitSixIsNeverRecordedAsProved() async throws {
        let closed = ["Test Suite 'All tests' started at 2026-10-02 06:49:41.667."] + Self.lostOne.dropLast()
            + ["Test Suite 'All tests' passed at 2026-10-02 06:49:41.668.", "\t Executed 2 tests, with 0 failures (0 unexpected) in 0.200 (0.204) seconds"]
        let held = try await RunInventoryNoteTests.indexedPackage()
        try Self.ignoreCache(in: held)
        let (_, thrown) = try await RunInventoryNoteTests.run(in: held, printing: closed, exiting: 0, extraArguments: ["--package-path", held.path], flags: Self.flags, finished: { _ in })
        let unheld = try await RunInventoryNoteTests.indexedPackage()
        try Self.ignoreCache(in: unheld)
        _ = try await RunInventoryNoteTests.run(in: unheld, printing: closed, exiting: 0, extraArguments: ["--package-path", unheld.path])

        #expect(thrown == ExitCode(6))
        #expect(!RunLedger.inRepository(at: unheld).records().isEmpty, "the control run files a proof")
        #expect(RunLedger.inRepository(at: held).records().isEmpty)
    }

    /// A check that could not run (over its budget) is unclean under the flag.
    @Test
    func aSkippedCheckExitsSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo", "testThree"]), exiting: 0, flags: Self.flags, inventoryBudget: 0)

        #expect(thrown == ExitCode(6))
        #expect(recorded.printed.contains("inventory: not checked — bringing the index up to date and reconciling took longer than 0 s"))
    }

    /// The progress file ends on the code the run exits with.
    @Test
    func theProgressFileEndsOnSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let seen = Codes()
        let (_, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: Self.lostOne, exiting: 0, flags: Self.flags, finished: { seen.add($0) })

        #expect(thrown == ExitCode(6))
        #expect(seen.values == [6])
    }

    /// A run the inventory would bound but whose package directory is spelled through a variable says it was not checked, and under the flag exits 6.
    @Test
    func aPackageDirectoryThroughAVariableExitsSixUnderTheFlag() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo", "testThree"]), exiting: 0, extraArguments: ["--package-path", "$PKG"], flags: Self.flags)

        #expect(thrown == ExitCode(6))
        #expect(recorded.printed.contains("inventory: not checked — the package directory is spelled through a variable"))
    }

    /// The paths that return before a test run starts cannot hold it to the inventory, so the combination is refused.
    @Test(arguments: [
        ["--without", "Sources", "--", "swift", "test"],
        ["--without-line", "Sources/A.swift:1", "--", "swift", "test"],
        ["--restore"],
    ])
    func theFlagWithASetAsideOrRestoreIsRefused(arguments: [String]) throws {
        var command = try RunCommand.parse(["--require-inventory"] + arguments)
        command.output = RecordedOutput().output

        do {
            try command.run()
            Issue.record("the combination ran")
        } catch let error as ValidationError {
            #expect(error.message.contains("run --require-inventory takes no --without, --without-line or --restore"))
        }
    }

    /// A narrowed `xcodebuild` run is a filtered run, not one bounded by its scheme.
    @Test(arguments: [["-only-testing:AppTests/Foo"], ["-skip-testing:AppTests/Foo"], ["-testPlan", "Plan"]])
    func aNarrowedXcodebuildRunSaysItWasFiltered(narrowing: [String]) {
        let absence = RunInventoryRequirement.absence(of: ["xcodebuild", "test", "-scheme", "App"] + narrowing, report: nil)

        #expect(absence.line == "inventory: not checked — the run was filtered, so it does not run the whole inventory")
        #expect(!absence.unclean)
    }

    /// An unnarrowed `xcodebuild` run keeps the scheme's reason.
    @Test
    func anUnnarrowedXcodebuildRunSaysItsSchemeBoundsIt() {
        let absence = RunInventoryRequirement.absence(of: ["xcodebuild", "test", "-scheme", "App"], report: nil)

        #expect(absence.line.contains("bounded by its scheme"))
        #expect(!absence.unclean)
    }

    /// A parallel run did run every test; what is missing is the list in its log.
    @Test
    func aParallelRunSaysItsLogNamesOnlySomeOfTheTests() {
        let report = RunReport(errors: [], warnings: [], testFailures: [], summaryLines: [], contract: .diagnostics, verdict: nil, tally: nil, totalLines: 0, testOutcomes: RunTestOutcomes(), parallelSwiftTest: true)
        let absence = RunInventoryRequirement.absence(of: ["swift", "test", "--parallel"], report: report)

        #expect(absence.line == "inventory: not checked — a --parallel run's log names only some of the tests it ran, so there is no list to reconcile")
        #expect(!absence.unclean)
    }
}

private extension RunRequireInventoryRecordTests {
    /// The exit codes a progress file ended on, handed back out of a closure.
    final class Codes: @unchecked Sendable {
        private let lock = NSLock()
        private var codes: [Int32] = []

        var values: [Int32] {
            lock.withLock { codes }
        }

        func add(_ code: Int32) {
            lock.withLock { codes.append(code) }
        }
    }
}
