//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

@Suite(.temporaryDirectories)
struct FlakesQueryTests {
    private static func run(
        kind: String = "swift test",
        exit: Int = 0,
        failed: [String] = [],
        day: String = "2026-08-20",
        tree: String? = nil,
        total: Int? = nil,
        recorded: Bool = true
    ) -> String {
        var object: [String: Any] = ["kind": kind, "exit": exit, "ms": 100, "ts": "\(day)T10:00:00Z", "root": "/repo/a"]
        if let tree {
            object["tree"] = tree
            object["invocation"] = "all"
        }
        if recorded {
            object["failed"] = failed
            object["failed_total"] = total ?? failed.count
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func render(_ lines: [String], query: String?, root: String? = nil, redactor: Redactor? = nil) throws -> String {
        let file = try TemporaryDirectory.make("flakes-query").appendingPathComponent("flakes.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return RunFailureHistoryReport.render(fileURL: file, root: root, redactor: redactor, query: query)
    }

    @Test
    func aQueryPrintsTheRealNameAndItsSameTreePopulationLine() throws {
        let name = "Gizmo/Depot/restock()"
        let rendered = try Self.render([
            Self.run(exit: 1, failed: [name], day: "2026-08-21", tree: "t1"),
            Self.run(tree: "t1"),
            Self.run(tree: "t1"),
        ], query: "restock")

        #expect(rendered.contains("`restock` — 1 test recorded failing"), "\(rendered)")
        #expect(rendered.contains("over 3 runs that recorded which tests failed"), "\(rendered)")
        #expect(rendered.contains("\n\(name)\n"), "\(rendered)")
        #expect(rendered.contains("  swift test — failed 1 of 3 runs · last 2026-08-21 · same tree: failed and passed on one tree"), "\(rendered)")
    }

    @Test
    func aTestThatFailedInEveryRunIsAnsweredAlthoughTheListingOmitsIt() throws {
        let lines = [
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"], tree: "t1"),
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"], day: "2026-08-22", tree: "t2"),
        ]
        let listed = try Self.render(lines, query: nil)
        let rendered = try Self.render(lines, query: "spins")

        #expect(listed.contains("spins()") == false, "\(listed)")
        #expect(rendered.contains("  swift test — failed 2 of 2 runs · last 2026-08-22 · failed in every run on recorded trees"), "\(rendered)")
    }

    @Test
    func aDotInTheQueryMatchesASlashInTheName() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"]),
            Self.run(),
        ], query: "Depot.restock")

        #expect(rendered.contains("Gizmo/Depot/restock()"), "\(rendered)")
        #expect(rendered.contains("1 test recorded failing"), "\(rendered)")
        #expect(rendered.contains("failed 1 of 2 runs · last 2026-08-20 · tree unknown"), "\(rendered)")
    }

    @Test
    func aTreelessPopulationNamesItsPoolWhenTheTestFailedInEveryRun() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"]),
            Self.run(tree: "t1"),
            Self.run(tree: "t1"),
        ], query: "spins")

        #expect(rendered.contains("failed 1 of 1 run · last 2026-08-20 · tree unknown, failed in every run"), "\(rendered)")
    }

    @Test
    func aSameTreeLineStatesFailuresOnTreesItNeverPassedOn() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"], day: "2026-08-20", tree: "t1"),
            Self.run(tree: "t1"),
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"], day: "2026-08-25", tree: "t2"),
        ], query: "spins")

        #expect(rendered.contains("same tree: failed and passed on one tree; also failed 1 time on trees or command lines it never passed on, last 2026-08-25"), "\(rendered)")
        #expect(rendered.contains("failed 1 of 2 runs · last 2026-08-20 ·"), "\(rendered)")
    }

    @Test
    func aRunWhoseNamesWerePastTheCapButNamesTheTestIsNotAFalseNo() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Widget/spins()"], total: 60),
            Self.run(),
        ], query: "spins")

        #expect(rendered.contains("also named failing by 1 run not counted above: 1 with names past the log's cap"), "\(rendered)")
        #expect(rendered.contains("no counted run recorded a matching test failing"), "\(rendered)")
        #expect(rendered.contains("no run recorded") == false, "\(rendered)")
    }

    @Test
    func aRunUnderAKindNamingNoActionButNamingTheTestIsNotAFalseNo() throws {
        let rendered = try Self.render([
            Self.run(kind: "xcodebuild", exit: 1, failed: ["Gizmo/Widget/spins()"]),
            Self.run(),
        ], query: "spins")

        #expect(rendered.contains("also named failing by 1 run not counted above: 1 under a kind that names no action"), "\(rendered)")
        #expect(rendered.contains("no counted run recorded a matching test failing"), "\(rendered)")
        #expect(rendered.contains("no run recorded") == false, "\(rendered)")
    }

    @Test
    func aQueryIsAnsweredWhenNoRunWasCountedButARunNamedTheTest() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"], total: 60),
        ], query: "Depot.restock")

        #expect(rendered.contains("`Depot.restock` — no counted run recorded a matching test failing"), "\(rendered)")
        #expect(rendered.contains("also named failing by 1 run not counted above: 1 with names past the log's cap"), "\(rendered)")
        #expect(rendered.contains("over 0 runs") == false, "\(rendered)")
    }

    @Test
    func runsThatCannotSayAreCountedBesideCleanRuns() throws {
        let rendered = try Self.render([
            Self.run(),
            Self.run(),
            Self.run(recorded: false),
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"], total: 60),
        ], query: "spins")

        #expect(rendered.contains("2 runs cannot say: 1 recorded no test names, 1 withheld names past the cap"), "\(rendered)")
        #expect(rendered.contains("no counted run recorded a matching test failing"), "\(rendered)")
        #expect(rendered.contains("also named") == false, "\(rendered)")
    }

    @Test
    func aQueryWithNoIdentifierCharacterIsRefused() {
        for query in [".", "/", "()", ""] {
            #expect(RunFailureHistoryReport.problem(withQuery: query) == "a query names a test: give at least one letter, digit or underscore", "\(query)")
        }

        #expect(RunFailureHistoryReport.problem(withQuery: "Depot.restock") == nil)
    }

    @Test
    func aQueryMatchingNothingSaysSoOverTheMeasuredRuns() throws {
        let rendered = try Self.render([
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"]),
            Self.run(),
        ], query: "Widget")

        #expect(rendered.contains("`Widget` — no run recorded a matching test failing, over 2 runs that recorded which tests failed"), "\(rendered)")
        #expect(rendered.contains("restock") == false, "\(rendered)")
    }

    @Test
    func moreThanTenMatchesPrintTenAndCountTheRest() throws {
        let names = (1 ... 12).map { "Gizmo/Widget/case\($0)()" }
        let rendered = try Self.render([Self.run(exit: 1, failed: names), Self.run()], query: "Widget")

        #expect(rendered.contains("12 tests recorded failing"), "\(rendered)")
        #expect(rendered.split(separator: "\n").filter { $0.hasPrefix("Gizmo/Widget/") }.count == 10, "\(rendered)")
        #expect(rendered.contains("… and 2 more tests match — narrow the query"), "\(rendered)")
    }

    @Test
    func theRootStaysRedactedWhileTheMatchedNamePrintsReal() throws {
        let lines = [
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"]),
            Self.run(),
        ]
        let redacted = try Self.render(lines, query: "restock", root: "/repo/a", redactor: .standard(saltFile: Self.saltFile()))
        let plain = try Self.render(lines, query: "restock", root: "/repo/a")

        #expect(redacted.contains("(in repo-"), "\(redacted)")
        #expect(redacted.contains("/repo/a") == false, "\(redacted)")
        #expect(redacted.contains("\nGizmo/Depot/restock()\n"), "\(redacted)")
        #expect(plain.contains("(in /repo/a)"), "\(plain)")
    }

    @Test
    func withoutAQueryTheListingIsUnchanged() throws {
        let lines = [
            Self.run(exit: 1, failed: ["Gizmo/Depot/restock()"]),
            Self.run(),
        ]
        let rendered = try Self.render(lines, query: nil)

        #expect(rendered.contains("1 test has both failed and passed, over 2 runs that recorded which tests failed"), "\(rendered)")
        #expect(rendered.contains("   last 2026-08-20   Gizmo/Depot/restock()"), "\(rendered)")
        #expect(rendered.contains("recorded failing") == false, "\(rendered)")
    }

    private static func saltFile() throws -> URL {
        try TemporaryDirectory.make("flakes-salt").appendingPathComponent("salt")
    }
}
