//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// The `raw:` line of a `swift-sure run --root <dir>` answer names its log by absolute path when the command was started outside `<dir>`, and relative to it when started inside.
///
/// Every test spawns the built binary: `--root` changes the process's directory, which would move every test running beside it.
@Suite(.temporaryDirectories)
struct RunRootLogPathTests {
    /// Started from another directory, the log is named by its absolute path under the root.
    @Test
    func aRunStartedOutsideTheRootNamesItsLogByAbsolutePath() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let started = try TemporaryDirectory.make("run-root-log-started")
        defer { try? FileManager.default.removeItem(at: started) }

        let result = try RunRootTests.sift(["run", "--root", fixture.root.path, "--", fixture.swift.path, "test"], in: started)

        #expect(result.status == 0, "\(result.output)")
        let raw = try #require(result.output.split(separator: "\n").first { $0.contains("raw: ") }, "\(result.output)")
        let underRoot = [fixture.root.path, RunRootTests.physical(fixture.root)].map { $0 + "/.swift-sure/runs/" }
        #expect(underRoot.contains { raw.contains($0) }, "\(raw)")
    }

    /// Started inside the root, the log keeps the relative spelling.
    @Test
    func aRunStartedInsideTheRootNamesItsLogRelatively() throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }

        let result = try RunRootTests.sift(["run", "--root", fixture.root.path, "--", fixture.swift.path, "test"], in: fixture.root)

        #expect(result.status == 0, "\(result.output)")
        let raw = try #require(result.output.split(separator: "\n").first { $0.contains("raw: ") }, "\(result.output)")
        #expect(raw.contains(" .swift-sure/runs/"), "\(raw)")
        #expect(!raw.contains(fixture.root.lastPathComponent + "/.swift-sure"), "\(raw)")
    }
}

extension RunRootLogPathTests {
    private struct Fixture {
        let root: URL
        let tools: URL
        let swift: URL

        static func make() throws -> Fixture {
            let root = try RunRootTests.makeRepository()
            let tools = try TemporaryDirectory.make("run-root-log-tools")
            let swift = tools.appendingPathComponent("swift")
            let script = "#!/bin/sh\nprintf '%s\\n' '◇ Test run started.' '✔ Test aTest() passed after 0.001 seconds.' '✔ Test run with 1 test in 1 suite passed after 0.001 seconds.'\nexit 0\n"
            try script.write(to: swift, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
            return Fixture(root: root, tools: tools, swift: swift)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: tools)
        }
    }
}
