//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers a Swift Testing suite nested in another, which `xcodebuild`'s enumeration lists one part per enclosing suite: `Target/Outer/Inner/function()`.
///
/// Measured on a real package scheme: a test in a suite nested in a suite enumerated as `Target/Outer/Inner/function()`, and the run was refused for not being three parts. Every spelling derived from the identifier has to keep that shape, and every reader that attributes an ending to one has to credit each nested test once.
struct NestedSuiteIdentifierTests {
    private func identifier(_ enumerated: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> TestIdentifier {
        try #require(TestIdentifier(enumerated: enumerated), sourceLocation: sourceLocation)
    }

    private func outcomes(reading lines: [String]) -> RunTestOutcomes {
        var read = RunTestOutcomes()
        for line in lines {
            read.read(line)
        }
        return read
    }

    private func plan(_ shards: [[TestIdentifier]], displayNames: [String: [TestIdentifier]] = [:]) -> ShardPlan {
        ShardPlan(
            shards: shards.enumerated().map { index, tests in
                ShardPlan.Shard(index: index + 1, tests: tests, predictedSeconds: 20 + Double(tests.count))
            },
            requestedShards: shards.count,
            overheadSeconds: 20,
            estimatedTests: 0,
            estimatedSeconds: 1,
            displayNames: displayNames,
            lowering: nil
        )
    }

    private func shard(_ lines: [String], exitCode: Int32 = 0) -> ShardOutcome {
        ShardOutcome(outcomes: outcomes(reading: lines), exitCode: exitCode, wallSeconds: 30, logPath: "/tmp/shard.log")
    }

    private func declared(suite: String, function: String, style: TestSymbol.Style, displayName: String? = nil) -> DeclaredTest {
        DeclaredTest(
            target: "GizmoTests",
            targetWasGuessed: false,
            suite: suite,
            function: function,
            style: style,
            displayName: displayName,
            disposition: .runs,
            path: "Tests/GizmoTests/WidgetTests.swift",
            line: 1
        )
    }

    // MARK: - Reading the enumeration's spelling

    @Test
    func aSuiteNestedOnceReadsTheSuitesBetweenTargetAndFunctionAsItsType() throws {
        let three = try identifier("GizmoTests/WidgetTests/same()")
        let four = try identifier("GizmoTests/WidgetTests/AlphaSuite/same()")
        let five = try identifier("GizmoTests/WidgetTests/AlphaSuite/NamedSuite/same(_:)")

        #expect(three.type == "WidgetTests")
        #expect(four.target == "GizmoTests")
        #expect(four.type == "WidgetTests/AlphaSuite")
        #expect(four.function == "same()")
        #expect(five.type == "WidgetTests/AlphaSuite/NamedSuite")
        #expect(five.function == "same(_:)")
        #expect(five.functionName == "same")
    }

    @Test
    func anEmptySuiteAnywhereInThePathIsRefused() {
        #expect(TestIdentifier(enumerated: "GizmoTests/WidgetTests//same()") == nil)
        #expect(TestIdentifier(enumerated: "GizmoTests//AlphaSuite/same()") == nil)
        #expect(TestIdentifier(enumerated: "GizmoTests/WidgetTests/AlphaSuite/") == nil)
    }

    /// A raw-identifier function's own `/` is inside its backticks, so it is no suite boundary however deep the suite is.
    @Test
    func aRawIdentifierFunctionKeepsItsOwnSlash() throws {
        let raw = try identifier("GizmoTests/WidgetTests/AlphaSuite/`reads a/b`()")

        #expect(raw.type == "WidgetTests/AlphaSuite")
        #expect(raw.function == "`reads a/b`()")
    }

    @Test
    func aNestedIdentifierRoundTripsByteForByte() throws {
        let spelled = "GizmoTests/WidgetTests/AlphaSuite/same()"
        let nested = try identifier(spelled)

        #expect(nested.enumerated == spelled)
        #expect(nested.onlyTestingArgument == "-only-testing:\(spelled)")
        #expect(TestIdentifier(enumerated: nested.enumerated) == nested)
    }

    // MARK: - Attributing a nested test's ending

    /// Two nested suites of one outer suite declaring the same function share one log name; one shard holding both credits each once by count, and neither is missing or counted twice.
    @Test
    func twoNestedSuitesSharingAFunctionInOneShardAreEachCreditedOnce() throws {
        let alpha = try identifier("GizmoTests/WidgetTests/AlphaSuite/same()")
        let beta = try identifier("GizmoTests/WidgetTests/NamedSuite/same()")
        let ended = ["Test same() started.", "Test same() passed after 0.001 seconds."]

        let merged = ShardMerge.reconcile(plan: plan([[alpha, beta]]), outcomes: [shard(ended + ended)])

        #expect(merged.counts == ShardReconciliation.Counts(expected: 2, ran: 2, passed: 2, failed: 0, skipped: 0, missing: 0, duplicated: 0))
        #expect(merged.missing.isEmpty)
        #expect(merged.isGreen)
    }

    /// Given a shard each, each nested test is named by its own shard's ending, which no other test of that shard can claim.
    @Test
    func twoNestedSuitesSharingAFunctionInTwoShardsAreEachNamedOnce() throws {
        let alpha = try identifier("GizmoTests/WidgetTests/AlphaSuite/same()")
        let beta = try identifier("GizmoTests/WidgetTests/NamedSuite/same()")

        let merged = ShardMerge.reconcile(plan: plan([[alpha], [beta]]), outcomes: [
            shard(["Test same() started.", "Test same() passed after 0.001 seconds."]),
            shard(["Test same() started.", "Test same() failed after 0.001 seconds with 1 issue."], exitCode: 1),
        ])

        #expect(merged.counts == ShardReconciliation.Counts(expected: 2, ran: 2, passed: 1, failed: 1, skipped: 0, missing: 0, duplicated: 0))
        #expect(merged.failed == [beta])
    }

    // MARK: - Joining the index to the enumeration

    /// The index writes a nested suite `WidgetTests.AlphaSuite`; joined to the enumeration under that spelling, a nested test's display name claims nothing.
    @Test
    func aNestedSwiftTestingDeclarationCarriesTheEnumerationsSpelling() throws {
        let swiftTesting = declared(suite: "WidgetTests.AlphaSuite", function: "same()", style: .swiftTesting)
        let xcTest = declared(suite: "WidgetTests.GizmoTests", function: "testTwo()", style: .xcTest)

        #expect(try swiftTesting.identifier == identifier("GizmoTests/WidgetTests/AlphaSuite/same()"))
        #expect(try xcTest.identifier == identifier("GizmoTests/WidgetTests.GizmoTests/testTwo()"))
    }

    @Test
    func aNestedTestEndingUnderItsLiteralIsCountedOntoIt() throws {
        let test = declared(suite: "WidgetTests.AlphaSuite", function: "same()", style: .swiftTesting, displayName: "Reads The Same")
        let enumerated = try identifier("GizmoTests/WidgetTests/AlphaSuite/same()")
        let names = try [#require(test.logName): [#require(test.identifier)]]

        let merged = ShardMerge.reconcile(plan: plan([[enumerated]], displayNames: names), outcomes: [
            shard(["Test \"Reads The Same\" started.", "Test \"Reads The Same\" passed after 0.001 seconds."]),
        ])

        #expect(merged.counts == ShardReconciliation.Counts(expected: 1, ran: 1, passed: 1, failed: 0, skipped: 0, missing: 0, duplicated: 0))
    }

    // MARK: - Selecting one again

    /// A re-run line repeats a failed test's enumerated spelling after `--only`, so that spelling must be one `--only` takes.
    @Test
    func aNestedSelectorIsTakenAndAFunctionBeforeTheLastPartIsNot() throws {
        #expect(throws: Never.self) {
            try TestInvocation.check(only: ["GizmoTests/WidgetTests/AlphaSuite/same()", "GizmoTests/WidgetTests/AlphaSuite"], skip: [], passThrough: [])
        }
        #expect(throws: TestInvocationError.self) {
            try TestInvocation.check(only: ["GizmoTests/WidgetTests/same()/AlphaSuite"], skip: [], passThrough: [])
        }
        #expect(throws: TestInvocationError.self) {
            try TestInvocation.check(only: ["GizmoTests/WidgetTests//same()"], skip: [], passThrough: [])
        }
    }
}
