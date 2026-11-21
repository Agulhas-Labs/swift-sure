//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how earlier green filtered runs of one tree count towards the `filtered:` line: their ids stand for suites this run left out, and a record written before the ids were filed still decodes.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachEarlierRunsTests {
    private static let widget = FilteredRunReachHintTests.widgetNames
    private static let gadget = ["testDoubling", "testExample"].map { "LibTests.GadgetTests/\($0)" }
    private static let oneFilter = ["swift", "test", "--filter", "WidgetTests"]
    private static var covered: String {
        "  filtered: every suite reaching the change has passed on this tree (this run and %@)"
    }

    private static func lines(_ names: [String], arguments: [String] = oneFilter, root: URL, earlier: [[String]]) -> [String] {
        let report = FilteredRunReachHintTests.report(names, invokedAs: arguments)
        let outcome = RunOutcome(kind: .swiftTest, logKey: "swift test", exitCode: 0, report: report, log: nil, repositoryRoot: nil)
        return FilteredRunReachHint.lines(after: outcome, selector: RunTestSelector.named(in: arguments), repositoryRoot: root, budget: 30, earlier: earlier)
    }

    @Test
    func aSuiteAnEarlierRunCoveredIsNotNamedWhileAnotherStillIs() async throws {
        let root = try await FilteredRunReachHintTests.checkout()
        try TestSources.write(FilteredRunReachHintTests.xctestSource("GizmoTests", ["testOne"]), to: "Tests/LibTests/GizmoTests.swift", in: root)
        try await SiftEngine(directory: root).ensureFresh()

        let alone = Self.lines(Self.widget, root: root, earlier: [])
        let withEarlier = Self.lines(Self.widget, root: root, earlier: [Self.gadget])

        #expect(alone.first?.contains("LibTests.GadgetTests") == true, "\(alone)")
        #expect(withEarlier.first?.contains("LibTests.GadgetTests") == false, "\(withEarlier)")
        #expect(withEarlier.first?.contains("LibTests.GizmoTests") == true, "\(withEarlier)")
    }

    @Test
    func anEarlierRunThatCoversEverySuiteLeftOutSaysSoAndIsCounted() async throws {
        let root = try await FilteredRunReachHintTests.checkout()

        let one = Self.lines(Self.widget, root: root, earlier: [Self.gadget])

        #expect(one == [String(format: Self.covered, "1 earlier run")])
    }

    @Test
    func twoEarlierRunsThatCoverSomethingAreCountedAndOneThatCoversNothingIsNot() async throws {
        let root = try await FilteredRunReachHintTests.checkout()
        let unrelated = ["LibTests.GizmoTests/testA"]

        let two = Self.lines(Self.widget, root: root, earlier: [[Self.gadget[0]], [Self.gadget[1]], unrelated])
        let one = Self.lines(Self.widget, root: root, earlier: [Self.gadget, unrelated])

        #expect(two == [String(format: Self.covered, "2 earlier runs")])
        #expect(one == [String(format: Self.covered, "1 earlier run")])
    }

    @Test
    func anEarlierRunThatCoveredPartOfASuiteLeavesTheRestNamed() async throws {
        let root = try await FilteredRunReachHintTests.checkout()

        let lines = Self.lines(Self.widget, root: root, earlier: [[Self.gadget[0]]])

        #expect(lines.first?.contains("LibTests.GadgetTests (1 of 2 ran)") == true, "\(lines)")
    }

    @Test
    func aSuiteRanInPartHereAndInRestByAnEarlierRunIsRunInFull() async throws {
        let root = try await FilteredRunReachHintTests.checkout()
        let arguments = ["swift", "test", "--filter", "testA|testB"]

        let lines = Self.lines(Array(Self.widget.prefix(2)), arguments: arguments, root: root, earlier: [["LibTests.WidgetTests/testGamma"] + Self.gadget])

        #expect(lines == [String(format: Self.covered, "1 earlier run")])
    }

    @Test
    func aRecordWrittenBeforeRanWasFiledDecodesWithNone() throws {
        let record = RunLedger.Record(tree: "abc", command: "swift test", toolchain: "t", finishedAt: Date(timeIntervalSince1970: 100), log: nil, milliseconds: 5, ran: ["A.B/c"])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        #expect(object["ran"] as? [String] == ["A.B/c"])
        object["ran"] = nil
        let decoded = try JSONDecoder().decode(RunLedger.Record.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.ran == nil)
        #expect(decoded.tree == "abc")
    }
}
