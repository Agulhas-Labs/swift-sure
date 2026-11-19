//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// A run whose test process crashed names the tests it left unfinished; `flakes` counts it as a crash, apart from the runs that cannot say.
@Suite(.temporaryDirectories)
struct FlakesCrashedRunsTests {
    private static func run(exit: Int = 1, crashed: [String]? = nil, crashedTotal: Int? = nil, failed: [String]? = nil, day: String = "2026-08-20") -> String {
        var object: [String: Any] = ["kind": "swift test", "exit": exit, "ms": 100, "ts": "\(day)T10:00:00Z", "root": "/repo/a"]
        if let crashed {
            object["crashed"] = crashed
            object["crashed_total"] = crashedTotal ?? crashed.count
        }
        if let failed {
            object["failed"] = failed
            object["failed_total"] = failed.count
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func render(_ lines: [String], query: String?, redactor: Redactor? = nil) throws -> String {
        let file = try TemporaryDirectory.make("flakes-crashed").appendingPathComponent("flakes.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return RunFailureHistoryReport.render(fileURL: file, root: nil, redactor: redactor, query: query)
    }

    @Test
    func aTestThatFailedAndCrashedShowsBoth() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(failed: ["Gizmo/Depot/restock()"]),
            Self.run(crashed: ["Gizmo/Depot/restock()"], day: "2026-08-22"),
        ], query: "restock")

        #expect(rendered.contains("Gizmo/Depot/restock()\n  crashed in 1 run · last 2026-08-22\n  swift test — failed 1 of 2 runs"), "\(rendered)")
    }

    @Test
    func theCrashedLineShowsFiveNamesThenHowManyMore() throws {
        let names = ["a", "b", "c", "d", "e", "f"].map { "Gizmo/Widget/\($0)()" }
        let rendered = try Self.render([Self.run(crashed: names), Self.run(crashed: ["Gizmo/Widget/f()"])], query: "Widget")

        #expect(rendered.contains("2 runs crashed in: Gizmo/Widget/f() (2), Gizmo/Widget/a() (1), Gizmo/Widget/b() (1), Gizmo/Widget/c() (1), Gizmo/Widget/d() (1), +1 more"), "\(rendered)")
    }

    @Test
    func theReportRedactsCrashedNames() throws {
        let rendered = try Self.render([Self.run(exit: 0, failed: []), Self.run(crashed: ["Gizmo/Depot/restock()"])], query: nil, redactor: Redactor(salt: Data("crash-salt".utf8)))

        #expect(rendered.contains("1 run crashed in: "), "\(rendered)")
        #expect(!rendered.contains("restock"), "\(rendered)")
    }

    @Test
    func crashedRunsAreNamedAndLeftOutOfCannotSay() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(crashed: ["Gizmo/Depot/restock()"]),
            Self.run(crashed: ["Gizmo/Depot/restock()"], day: "2026-08-22"),
        ], query: "spins")

        #expect(rendered.contains("2 runs crashed in: Gizmo/Depot/restock() (2)"), "\(rendered)")
        #expect(!rendered.contains("cannot say"), "\(rendered)")
    }

    @Test
    func aCrashThatNamedNothingStaysUnrecorded() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(),
            Self.run(crashed: ["Gizmo/Widget/spins()"]),
        ], query: "spins")

        #expect(rendered.contains("1 run crashed in: Gizmo/Widget/spins() (1)"), "\(rendered)")
        #expect(rendered.contains("1 run cannot say: 1 recorded no test names"), "\(rendered)")
    }

    @Test
    func theReportNamesCrashedRunsApartFromTheUnrecorded() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(),
            Self.run(crashed: ["Gizmo/Depot/restock()"]),
            Self.run(crashed: ["Gizmo/Depot/restock()"], day: "2026-08-22"),
        ], query: nil)

        #expect(rendered.contains("2 runs crashed in: Gizmo/Depot/restock() (2) — the tests each crash left unfinished"), "\(rendered)")
        #expect(rendered.contains("1 run recorded nothing about which tests failed"), "\(rendered)")
    }

    @Test
    func aTestOnlyEverSeenInCrashesIsAnswered() throws {
        let rendered = try Self.render([
            Self.run(crashed: ["Gizmo/Depot/restock()"]),
            Self.run(crashed: ["Gizmo/Depot/restock()", "Gizmo/Widget/spins()"], day: "2026-08-22"),
        ], query: "restock")

        #expect(rendered.contains("Gizmo/Depot/restock()\n  crashed in 2 runs · last 2026-08-22"), "\(rendered)")
        #expect(!rendered.contains("Gizmo/Widget/spins()\n"), "\(rendered)")
    }

    @Test
    func aSuiteQueryCountsATestSeenOnlyCrashingBareAsCarryingNoSuite() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(crashed: ["restock()"]),
        ], query: "Depot.restock")

        #expect(rendered.contains("1 test in scope carries no suite (crash records never do; failures recorded before this version, or unresolved) and could not be matched by one"), "\(rendered)")
    }

    @Test
    func aCrashThatLeftMoreUnfinishedThanTheLogNamesSaysSoInTheQueryAndTheReport() throws {
        let lines = [
            Self.run(crashed: ["Gizmo/Depot/restock()", "Gizmo/Widget/spins()", "Gizmo/Widget/turns()"], crashedTotal: 60),
            Self.run(crashed: ["Gizmo/Depot/restock()"], day: "2026-08-22"),
        ]
        let suffix = "; 1 of them left more tests unfinished than the log lists"

        let query = try Self.render(lines, query: "restock")
        let report = try Self.render(lines, query: nil)

        #expect(query.contains("2 runs crashed in: Gizmo/Depot/restock() (2), Gizmo/Widget/spins() (1), Gizmo/Widget/turns() (1)\(suffix)"), "\(query)")
        #expect(report.contains("2 runs crashed in: Gizmo/Depot/restock() (2), Gizmo/Widget/spins() (1), Gizmo/Widget/turns() (1)\(suffix) — the tests each crash"), "\(report)")
    }

    /// A line counting one crashed run says the run itself left more unfinished, not "1 of them".
    @Test
    func aLoneCrashPastTheCapSaysItLeftMore() throws {
        let rendered = try Self.render([Self.run(crashed: ["Gizmo/Depot/restock()"], crashedTotal: 60)], query: nil)

        #expect(rendered.contains("1 run crashed in: Gizmo/Depot/restock() (1); it left more tests unfinished than the log lists"), "\(rendered)")
    }

    @Test
    func aCrashThatNamedEveryUnfinishedTestAddsNoSuffix() throws {
        let rendered = try Self.render([Self.run(crashed: ["Gizmo/Depot/restock()"])], query: nil)

        #expect(!rendered.contains("of them left more tests unfinished"), "\(rendered)")
    }

    @Test
    func aRunWrittenWithAnEmptyCrashedListIsCountedUnrecordedNotCrashed() throws {
        let rendered = try Self.render([Self.run(exit: 0, failed: []), Self.run(crashed: [])], query: "spins")

        #expect(rendered.contains("1 run cannot say: 1 recorded no test names"), "\(rendered)")
        #expect(!rendered.contains("crashed in"), "\(rendered)")
    }
}
