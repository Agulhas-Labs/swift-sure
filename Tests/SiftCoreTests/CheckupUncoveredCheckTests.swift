//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The `uncovered` check as a pure function of the record, the tree key, the change and the clock.
struct CheckupUncoveredCheckTests {
    private static var path: String {
        "Sources/Kit/Shape.swift"
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var tree: TreeKey {
        TreeKey(value: "tree-a")
    }

    private static var rerun: String {
        "\(ProductName.current.binary) run --coverage --from 81c0d2e -- swift test"
    }

    private static func record(tree: String = "tree-a", counts: [Int: UInt64], unmeasured: [String] = [], age: TimeInterval = 60) -> CoverageRecord {
        CoverageRecord(tree: tree, command: ["swift", "test"], measured: [path: counts], unmeasured: unmeasured, measuredAt: now.addingTimeInterval(-age))
    }

    private static func check(_ record: CoverageRecord?, lines: [String: Set<Int>] = [path: [3, 4, 5]], range: String? = nil) -> CheckupOutcome {
        let changed = ChangedCode(declarations: [], lines: lines)
        return CheckupUncoveredCheck(record: record, tree: tree, changed: changed, base: "81c0d2e", testCommand: "swift test", range: range, now: now).outcome()
    }

    @Test
    func anUncoveredChangedLineIsAFindingQuotingTheChangedLinesLineWholeWithNoCommand() {
        let outcome = Self.check(Self.record(counts: [3: 2, 4: 0, 5: 2]))

        #expect(outcome.status == .checked(basis: nil, bound: nil))
        #expect(outcome.findings.count == 1)
        #expect(outcome.findings.first?.findingClass == .uncovered)
        #expect(outcome.findings.first?.text == "changed lines: 3 executable, 2 covered; uncovered: \(Self.path):4")
        #expect(outcome.findings.first?.command == "")
        #expect(outcome.findings.first?.location == nil)
    }

    @Test
    func theDiffCoveragePointerAppearsOnlyWhereTheLineEndsInMore() {
        let lines = Set(stride(from: 1, through: 13, by: 2))
        let counts = Dictionary(uniqueKeysWithValues: lines.map { ($0, UInt64(0)) })

        let outcome = Self.check(Self.record(counts: counts), lines: [Self.path: lines])

        #expect(outcome.findings.first?.text.hasSuffix(", +2 more") == true)
        #expect(outcome.findings.first?.command == "\(ProductName.current.binary) diff --coverage")
    }

    /// Pins that a checkup given a range prints no pointer on an omitted line, since `diff --coverage` takes no range.
    @Test
    func aRangeGivenLeavesTheOmittedLineWithNoPointerBecauseDiffCoverageTakesNone() {
        let lines = Set(stride(from: 1, through: 13, by: 2))
        let counts = Dictionary(uniqueKeysWithValues: lines.map { ($0, UInt64(0)) })

        let outcome = Self.check(Self.record(counts: counts), lines: [Self.path: lines], range: "main...HEAD")

        #expect(outcome.findings.first?.text.hasSuffix(", +2 more") == true)
        #expect(outcome.findings.first?.command == "")
    }

    /// Pins the coverage suggestion for a change in one nested package root: `run --root <dir>`, the root's own command.
    @Test
    func aNestedPackageRootGetsARootFlagOnTheCoverageSuggestion() {
        let changed = ChangedCode(declarations: [], lines: [Self.path: [3]])

        let outcome = CheckupUncoveredCheck(record: nil, tree: Self.tree, changed: changed, base: "81c0d2e", testCommand: "swift test", packageRoots: ["Sub"], now: Self.now).outcome()

        #expect(outcome.status == .notChecked(reason: "none recorded in this checkout — \(ProductName.current.binary) run --root Sub --coverage --from 81c0d2e -- swift test"))
    }

    /// Pins that a change across several package roots appends no coverage command, since one run records one package.
    @Test
    func aChangeAcrossPackageRootsAppendsNoCoverageCommand() {
        let changed = ChangedCode(declarations: [], lines: [Self.path: [3]])

        let outcome = CheckupUncoveredCheck(record: nil, tree: Self.tree, changed: changed, base: "81c0d2e", testCommand: "swift test", packageRoots: [".", "Sub"], now: Self.now).outcome()

        #expect(outcome.status == .notChecked(reason: "none recorded in this checkout"))
    }

    @Test
    func aRangeGivenAddsNoPointerWhereTheLineDoesNotEndInMore() {
        let outcome = Self.check(Self.record(counts: [3: 2, 4: 0, 5: 2]), range: "main...HEAD")

        #expect(outcome.findings.first?.command == "")
    }

    @Test
    func aRecordForAnotherTreeKeyIsNotUsedAndSaysWhy() {
        let outcome = Self.check(Self.record(tree: "tree-b", counts: [3: 0, 4: 0, 5: 0]))

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .notChecked(reason: "recorded for another change set — \(Self.rerun)"))
    }

    @Test
    func aChangedSwiftFileInNeitherSetMakesItAnotherChangeSet() {
        let lines = [Self.path: Set([3]), "Sources/Kit/Other.swift": Set([1])]

        let outcome = Self.check(Self.record(counts: [3: 0]), lines: lines)

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .notChecked(reason: "recorded for another change set — \(Self.rerun)"))
    }

    @Test
    func aRecordPastTheTrustWindowIsNotUsedAndSaysHowOld() {
        let age = RunLedger.trustWindow + 120

        let outcome = Self.check(Self.record(counts: [3: 0], age: age))

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .notChecked(reason: "recorded \(ProvedRunAnswer.elapsed(age)) ago, past the trust window — \(Self.rerun)"))
    }

    @Test
    func noRecordIsNotCheckedWithTheReason() {
        let outcome = Self.check(nil)

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .notChecked(reason: "none recorded in this checkout — \(Self.rerun)"))
    }

    @Test
    func unmeasuredChangedFilesAreCountedBesideTheCheck() {
        let lines = [Self.path: Set([3]), "Sources/Kit/Other.swift": Set([1])]

        let outcome = Self.check(Self.record(counts: [3: 1], unmeasured: ["Sources/Kit/Other.swift"]), lines: lines)

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .checked(basis: "1 file unmeasured", bound: nil))
    }

    @Test
    func everyChangedLineCoveredIsCheckedWithNoFinding() {
        let outcome = Self.check(Self.record(counts: [3: 1, 4: 1, 5: 1]))

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .checked(basis: nil, bound: nil))
    }

    @Test
    func aChangeWithNoExecutableLineIsCheckedWithNoFinding() {
        let outcome = Self.check(Self.record(counts: [9: 0]))

        #expect(outcome.findings.isEmpty)
        #expect(outcome.status == .checked(basis: nil, bound: nil))
    }
}
