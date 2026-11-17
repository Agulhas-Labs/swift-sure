//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Covers the rule one `--root` argument has to obey: it names one directory, for every log a command reads.
///
/// The two logs hold different sets of roots by construction, so resolving the same fragment separately against each let a single heading carry two repositories' numbers. Every test here is one of the three ways that showed.
@Suite(.temporaryDirectories)
struct LogScopeTests {
    // MARK: Fixtures

    private static func writeLines(_ lines: [String], named name: String) throws -> URL {
        let file = try TemporaryDirectory.make(name)
            .appendingPathComponent("\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func callLog(roots: [String]) throws -> URL {
        try writeLines(roots.map { root in
            line(["tool": "digest", "target": "Widget", "root": root, "ms": 5, "ok": true, "ts": "2026-08-18T10:00:00Z"])
        }, named: "log-scope-usage")
    }

    private static func runLog(roots: [String]) throws -> URL {
        try writeLines(roots.map { root in
            line(["kind": "swift test", "exit": 0, "ms": 900, "shown": 4, "total": 200, "root": root, "ts": "2026-08-18T11:00:00Z"])
        }, named: "log-scope-run")
    }

    private static func line(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    // MARK: One argument, one directory

    // MARK: What a refusal is allowed to print

    /// A machine-local path in a fixture, spelled with a home directory so the username is a thing the assertions can look for.
    private static let roots = [
        "/Users/hometester/Developer/Alpha/app",
        "/Users/hometester/Developer/Beta/app",
        "/Users/hometester/Developer/Solo",
    ]

    private static var redactor: Redactor {
        Redactor(salt: Data("log-scope-test-salt".utf8))
    }

    // MARK: Canonicalisation

    /// A directory nothing is standing at still compares equal to itself, which is what every fixture path in this suite depends on.
    @Test
    func aRootThatIsNotOnDiskStillResolves() throws {
        let scope = try LogScope.resolve("/work/Catalogue", among: ["/work/Catalogue"]).get()

        #expect(scope.path == "/work/Catalogue")
        #expect(scope.positions(of: ["/work/Catalogue", "/work/Catalogue/app", "/work/Cataloguebook"])
            == ["/work/Catalogue": .exact, "/work/Catalogue/app": .below])
    }

    // MARK: Fixtures
}
