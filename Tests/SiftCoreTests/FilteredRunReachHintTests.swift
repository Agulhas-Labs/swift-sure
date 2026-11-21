//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the line a `swift test --filter` run on a changed tree carries: the suites reaching the uncommitted change that the filter left out, beside the run's unchanged totals, verdict and exit code.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachHintTests {
    static let widgetNames = ["testA", "testB", "testGamma"].map { "-[LibTests.WidgetTests \($0)]" }
    private static let gadgetNames = ["testDoubling", "testExample"].map { "-[LibTests.GadgetTests \($0)]" }

    static func xctestSource(_ suite: String, _ tests: [String]) -> String {
        let functions = tests.map { "    func \($0)() {\n        _ = Widget()\n    }\n" }.joined(separator: "\n")
        return "import XCTest\n@testable import Lib\n\nfinal class \(suite): XCTestCase {\n\(functions)}\n"
    }

    /// `Widget` is referenced by `WidgetTests` (three tests) and `GadgetTests` (two); the index is built from the committed tree, which `dirty` then edits.
    static func checkout(dirty: Bool = true, indexed: Bool = true) async throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Lib\",\n    targets: [\n        .target(name: \"Lib\"),\n        .testTarget(name: \"LibTests\", dependencies: [\"Lib\"]),\n    ]\n)\n", to: "Package.swift", in: root)
        try TestSources.write("public struct Widget {\n    public init() {}\n}\n", to: "Sources/Lib/Core.swift", in: root)
        try TestSources.write(xctestSource("WidgetTests", ["testA", "testB", "testGamma"]), to: "Tests/LibTests/WidgetTests.swift", in: root)
        try TestSources.write(xctestSource("GadgetTests", ["testDoubling", "testExample"]), to: "Tests/LibTests/GadgetTests.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        if indexed {
            try await SiftEngine(directory: root).ensureFresh()
        }
        if dirty {
            try TestSources.write("public struct Widget {\n    public init() {}\n    public var size = 1\n}\n", to: "Sources/Lib/Core.swift", in: root)
        }
        return root
    }

    static func report(_ names: [String], failing: Bool = false, invokedAs arguments: [String]) -> RunReport {
        var lines = ["Test Suite 'Selected tests' started at 2000-01-01 12:00:00.346.", "Test Suite 'LibTests.xctest' started at 2000-01-01 12:00:00.346."]
        for (index, name) in names.enumerated() {
            lines.append("Test Case '\(name)' started.")
            if failing, index == 0 {
                lines.append("/tmp/Lib/Tests/LibTests/T.swift:4: error: \(name) : XCTAssertTrue failed")
                lines.append("Test Case '\(name)' failed (0.001 seconds).")
            } else {
                lines.append("Test Case '\(name)' passed (0.000 seconds).")
            }
        }
        let word = failing ? "failed" : "passed"
        let tally = "\t Executed \(names.count) tests, with \(failing ? 1 : 0) failures (0 unexpected) in 0.001 (0.001) seconds"
        lines += ["Test Suite 'LibTests.xctest' \(word) at 2000-01-01 12:00:00.347.", tally, "Test Suite 'Selected tests' \(word) at 2000-01-01 12:00:00.347.", tally]
        var filter = RunOutputFilter(invokedAs: arguments)
        filter.consume(Data((lines.joined(separator: "\n") + "\n").utf8))
        return filter.finish(exitCode: failing ? 1 : 0)
    }

    static func lines(_ names: [String], arguments: [String], root: URL, failing: Bool = false, budget: TimeInterval = 30) throws -> [String] {
        let report = report(names, failing: failing, invokedAs: arguments)
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: failing ? 1 : 0, report: report, log: nil, repositoryRoot: nil)
        return FilteredRunReachHint.lines(after: outcome, selector: RunTestSelector.named(in: arguments), repositoryRoot: root, budget: budget)
    }

    static let oneFilter = ["swift", "test", "--filter", "WidgetTests"]

    @Test
    func aFilteredRunOnAChangedTreeNamesTheReachingSuiteItLeftOut() async throws {
        let root = try await Self.checkout()
        let lines = try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root)

        #expect(lines == ["  filtered: the working tree changes Core.swift; 1 suite reaching it did not run — run swift test --filter LibTests.GadgetTests (swift-sure affected lists every suite)"])
    }

    @Test
    func aFailingFilteredRunGetsTheLineToo() async throws {
        let root = try await Self.checkout()
        let lines = try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root, failing: true)

        #expect(lines.count == 1)
        #expect(lines.first?.contains("LibTests.GadgetTests") == true)
    }

    @Test
    func aSuiteThatRanInPartIsNamedWithItsShare() async throws {
        let root = try await Self.checkout()
        let arguments = ["swift", "test", "--filter", "testA|testB"]
        let lines = try Self.lines(Array(Self.widgetNames.prefix(2)), arguments: arguments, root: root)

        let line = try #require(lines.first)

        #expect(line.contains("2 suites reaching it did not run in full: LibTests.WidgetTests (2 of 3 ran) — run swift test --filter LibTests.GadgetTests --filter LibTests.WidgetTests"))
    }

    @Test
    func aRunThatReachedEveryReachingSuiteGetsNoLine() async throws {
        let root = try await Self.checkout()

        #expect(try Self.lines(Self.widgetNames + Self.gadgetNames, arguments: ["swift", "test", "--filter", "LibTests"], root: root).isEmpty)
    }

    @Test
    func theLineNamesFiveSuitesAndCountsTheRest() throws {
        let suites = (1 ... 8).map { FilteredRunReachHint.Suite(filter: "LibTests.Suite\($0)", ran: 0, declared: 2) }
        let hint = FilteredRunReachHint(files: ["Sources/Lib/Core.swift", "Sources/Lib/More.swift", "Sources/Lib/Less.swift"], suites: suites)
        let line = try #require(hint.line)

        #expect(line.contains("changes Core.swift and 2 more files; 8 suites reaching it did not run"))
        #expect(line.contains("run swift test --filter LibTests.Suite1 --filter LibTests.Suite2 --filter LibTests.Suite3 --filter LibTests.Suite4 --filter LibTests.Suite5 (+3 more; swift-sure affected lists every suite)"))
        #expect(!line.contains("Suite6"))
        #expect(FilteredRunReachHint(files: ["A.swift"], suites: []).line == nil)
    }

    @Test
    func aCleanTreeGetsNoLine() async throws {
        let root = try await Self.checkout(dirty: false)

        #expect(try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root).isEmpty)
    }

    @Test
    func anUnfilteredRunGetsNoLine() async throws {
        let root = try await Self.checkout()

        #expect(try Self.lines(Self.widgetNames, arguments: ["swift", "test"], root: root).isEmpty)
    }

    @Test
    func aParallelRunGetsNoLine() async throws {
        let root = try await Self.checkout()

        #expect(try Self.lines(Self.widgetNames, arguments: Self.oneFilter + ["--parallel"], root: root).isEmpty)
    }

    /// A Swift Testing run whose event stream was not read cannot say which tests it ran, so nothing is guessed.
    @Test
    func aSwiftTestingRunWithNoEventStreamGetsNoLine() async throws {
        let root = try await Self.checkout()
        let arguments = ["swift", "test", "--filter", "aLogWithNoBannerIsNotAZero"]
        var filter = RunOutputFilter(invokedAs: arguments)
        try filter.consume(Data(TestSources.runOutput("swift-test-filter-one-unmatched").utf8))
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 0, report: filter.finish(exitCode: 0), log: nil, repositoryRoot: nil)

        #expect(FilteredRunReachHint.lines(after: outcome, selector: RunTestSelector.named(in: arguments), repositoryRoot: root, budget: 30).isEmpty)
    }

    @Test
    func aRunThatRanNoTestGetsNoLine() async throws {
        let root = try await Self.checkout()
        let arguments = ["swift", "test", "--filter", "aFailingTest"]
        let report = try TestSources.runReport("swift-test-no-match", invokedAs: arguments, exitCode: 0)
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 0, report: report, log: nil, repositoryRoot: nil)

        #expect(FilteredRunReachHint.lines(after: outcome, selector: RunTestSelector.named(in: arguments), repositoryRoot: root, budget: 30).isEmpty)
    }

    @Test
    func aCheckoutWithNoIndexGetsNoLineAndBuildsNone() async throws {
        let root = try await Self.checkout(indexed: false)
        let lines = try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root)

        #expect(lines.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: SiftPaths.cache(in: root).appendingPathComponent(SiftPaths.indexFileName).path))
    }

    /// The index is brought up to date before the walk: the dirty file's stored rows are read as the file stands now, so the index file is written.
    @Test
    func aStaleIndexIsBroughtUpToDateForTheLine() async throws {
        let root = try await Self.checkout()
        let database = SiftPaths.cache(in: root).appendingPathComponent(SiftPaths.indexFileName)
        let before = try #require(FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as? Date)
        try TestSources.write("public struct Widget {\n    public init() {}\n    public var size = 2\n    public var weight = 3\n}\n", to: "Sources/Lib/Core.swift", in: root)

        #expect(try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root).count == 1)
        let after = try #require(FileManager.default.attributesOfItem(atPath: database.path)[.modificationDate] as? Date)
        #expect(after > before)
    }

    @Test
    func aWalkPastItsBudgetDropsTheLineAndNothingElse() async throws {
        let root = try await Self.checkout()

        #expect(try Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root, budget: -1).isEmpty)
    }

    /// The line sits under the totals and changes nothing above it: the first line, the totals and the exit code are the same with and without it.
    @Test
    func theLineNeverChangesTheTotalsTheVerdictOrTheExitCode() async throws {
        let root = try await Self.checkout()
        let report = Self.report(Self.widgetNames, failing: true, invokedAs: Self.oneFilter)
        let selector = try #require(RunTestSelector.named(in: Self.oneFilter))
        let note = try #require(Self.lines(Self.widgetNames, arguments: Self.oneFilter, root: root, failing: true).first)
        let directory = URL(fileURLWithPath: "/Users/dev/Lib")
        let plain = RunReportRenderer(kind: .swiftTest, workingDirectory: directory, selector: selector).render(report, exitCode: 1, logURL: nil).split(separator: "\n").map(String.init)
        let noted = RunReportRenderer(kind: .swiftTest, workingDirectory: directory, selector: selector, inventory: [note]).render(report, exitCode: 1, logURL: nil).split(separator: "\n").map(String.init)

        // The raw line counts the lines the answer printed, so it is the one line that moves with a note.
        #expect(noted.filter { $0 != note && !$0.hasPrefix("raw: ") } == plain.filter { !$0.hasPrefix("raw: ") })
        #expect(noted.first == plain.first)
        #expect(noted.first { $0.hasPrefix("totals: ") } == plain.first { $0.hasPrefix("totals: ") })
        #expect(selector.ownExitCode(report, exitCode: 1) == nil)
    }
}
