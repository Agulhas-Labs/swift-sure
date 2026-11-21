//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// The note that a suite query could not reach suiteless names counts only the names the query could have matched, crash names included.
@Suite(.temporaryDirectories)
struct FlakesSuiteNoteScopeTests {
    private static func run(exit: Int = 1, crashed: [String]? = nil, failed: [String]? = nil, suites: [String: String]? = nil) -> String {
        var object: [String: Any] = ["kind": "swift test", "exit": exit, "ms": 100, "ts": "2026-08-20T10:00:00Z", "root": "/repo/a"]
        if let crashed {
            object["crashed"] = crashed
            object["crashed_total"] = crashed.count
        }
        if let failed {
            object["failed"] = failed
            object["failed_total"] = failed.count
        }
        if let suites {
            object["failedSuites"] = suites
        }
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func render(_ lines: [String], query: String?) throws -> String {
        let file = try TemporaryDirectory.make("flakes-suite-note").appendingPathComponent("flakes.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return RunFailureHistoryReport.render(fileURL: file, root: nil, redactor: nil, query: query)
    }

    @Test
    func aMemberQueryIgnoresSuitelessNamesThatDoNotContainTheMember() throws {
        let rendered = try Self.render([
            Self.run(exit: 0, failed: []),
            Self.run(crashed: ["spins()", "polishes()", "Gizmo/Depot/restock()"]),
        ], query: "Depot.restock")

        #expect(rendered.contains("Gizmo/Depot/restock()"), "\(rendered)")
        #expect(!rendered.contains("carry no suite"), "\(rendered)")
        #expect(!rendered.contains("carries no suite"), "\(rendered)")
    }

    @Test
    func aMemberQueryStillCountsASuitelessNameContainingTheMember() throws {
        let rendered = try Self.render([Self.run(exit: 0, failed: []), Self.run(crashed: ["restock()", "spins()"])], query: "Depot.restock")

        #expect(rendered.contains("1 test in scope carries no suite"), "\(rendered)")
    }

    @Test
    func aBareSuiteQueryCountsEverySuitelessName() throws {
        let rendered = try Self.render([Self.run(exit: 0, failed: []), Self.run(crashed: ["restock()", "spins()"])], query: "Depot")

        #expect(rendered.contains("2 tests in scope carry no suite"), "\(rendered)")
    }

    @Test
    func aCrashNameAFailureFiledUnderASuiteStaysMatchable() throws {
        let rendered = try Self.render([
            Self.run(failed: ["restock()"], suites: ["restock()": "Depot"]),
            Self.run(crashed: ["restock()"]),
        ], query: "Depot.restock")

        #expect(rendered.contains("crashed in 1 run"), "\(rendered)")
        #expect(!rendered.contains("no suite"), "\(rendered)")
    }

    @Test
    func theMoreTestsLineFollowsTheCrashOnlyLines() throws {
        let failing = (1 ... 11).map { "restock\($0)()" }
        let rendered = try Self.render([Self.run(failed: failing), Self.run(crashed: ["restock12()"])], query: "restock")

        let crash = try #require(rendered.range(of: "restock12()"), "\(rendered)")
        let more = try #require(rendered.range(of: "… and 1 more tests match"), "\(rendered)")

        #expect(crash.upperBound <= more.lowerBound, "\(rendered)")
    }

    @Test
    func aWindowWithNoCountedRunStillPrintsTheSuiteNote() throws {
        let rendered = try Self.render([Self.run(crashed: ["restock()", "Gizmo/Depot/restock()"])], query: "Depot.restock")

        #expect(rendered.contains("carries no suite"), "\(rendered)")
    }

    @Test
    func aSuiteQueryWhoseOnlyCandidateIsABareCrashNameAnswersWithTheNote() throws {
        let rendered = try Self.render([Self.run(crashed: ["restock()"])], query: "Depot.restock")

        #expect(rendered.hasPrefix("`Depot.restock` — no counted run recorded a matching test failing"), "\(rendered)")
        #expect(rendered.contains("1 test in scope carries no suite"), "\(rendered)")
    }
}
