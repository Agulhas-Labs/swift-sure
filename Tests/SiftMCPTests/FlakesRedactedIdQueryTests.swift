//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

@Suite(.temporaryDirectories)
struct FlakesRedactedIdQueryTests {
    private static var name: String {
        "Gizmo/Depot/restock()"
    }

    private static var redactor: Redactor {
        Redactor(salt: Data("fixed-salt".utf8))
    }

    private static func run(exit: Int = 0, failed: [String] = [], stamp: String = "2026-08-20T10:00:00Z") -> String {
        let object: [String: Any] = [
            "kind": "swift test", "exit": exit, "ms": 100, "ts": stamp, "root": "/repo/a",
            "tree": "t1", "invocation": "all", "failed": failed, "failed_total": failed.count,
        ]
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    private static func render(query: String?, redactor: Redactor?, since: String? = nil) throws -> String {
        let file = try TemporaryDirectory.make("flakes-id").appendingPathComponent("flakes.jsonl")
        let lines = [run(exit: 1, failed: [name]), run(), run(stamp: "2026-08-22T10:00:00Z"), run(stamp: "2026-08-23T10:00:00Z")]
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return RunFailureHistoryReport.render(fileURL: file, since: since, redactor: redactor, query: query, ids: Self.redactor)
    }

    @Test
    func theIdTheRedactedSummaryPrintsAnswersWithThatTestsName() throws {
        let id = Self.redactor.test(Self.name)
        let summary = try Self.render(query: nil, redactor: Self.redactor)
        #expect(summary.contains(id), "\(summary)")
        #expect(summary.contains("or flakes <id> for one"), "\(summary)")

        let rendered = try Self.render(query: id, redactor: Self.redactor)
        #expect(rendered.contains("`\(id)` — 1 test recorded failing"), "\(rendered)")
        #expect(rendered.contains("\n\(Self.name)\n"), "\(rendered)")
    }

    @Test
    func theIdAnswersWhenRenderedUnredacted() throws {
        let rendered = try Self.render(query: Self.redactor.test(Self.name), redactor: nil)

        #expect(rendered.contains("\n\(Self.name)\n"), "\(rendered)")
    }

    @Test
    func anUnknownWellFormedIdIsAnsweredAsAnId() throws {
        let rendered = try Self.render(query: "test-000000", redactor: Self.redactor)

        #expect(rendered.contains("`test-000000` — no run recorded a matching test failing, over 4 runs"), "\(rendered)")
        #expect(rendered.contains("ids are per machine"), "\(rendered)")
        #expect(rendered.contains("no counted run") == false, "\(rendered)")
    }

    @Test
    func anIdOutsideTheSinceWindowKeepsTheScopeInItsAnswer() throws {
        let rendered = try Self.render(query: Self.redactor.test(Self.name), redactor: Self.redactor, since: "2026-08-21")

        #expect(rendered.contains("(since 2026-08-21)"), "\(rendered)")
        #expect(rendered.contains("over 2 runs"), "\(rendered)")
        #expect(rendered.contains("on this machine") == false, "\(rendered)")
    }

    @Test
    func aQueryThatIsNotATokenStillMatchesBySubstring() throws {
        let rendered = try Self.render(query: "test-foo", redactor: Self.redactor)
        #expect(rendered.contains("no recorded failing test has this id") == false, "\(rendered)")
        let plain = try Self.render(query: "restock", redactor: Self.redactor)
        #expect(plain.contains("\n\(Self.name)\n"), "\(plain)")
    }
}
