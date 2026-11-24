//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A Swift file changed while a `Bash` call ran counts as an edit to the `Stop` gate, as one made through `Edit` does.
@Suite(.temporaryDirectories)
struct StopGateBashEditTests {
    private static var sed: String {
        "sed -i '' s/a/b/ Sources/App/Depot.swift"
    }

    /// Changes `Depot.swift` through `change` a moment after the fixture was made, so its other files predate the returned instant, and returns that instant.
    private static func settle(_ fixture: StopGateFixture, _ change: (StopGateFixture) throws -> Void = StopGateBashEditTests.change) throws -> Date {
        Thread.sleep(forTimeInterval: 0.05)
        let mark = Date()
        try change(fixture)
        return mark
    }

    private static func change(_ fixture: StopGateFixture) throws {
        try "struct Depot { var a = 1 }\n".write(toFile: fixture.depot, atomically: true, encoding: .utf8)
    }

    /// What the hook printed for a transcript whose one `Bash` call ran from `start` to `end` seconds from the instant just before `Depot.swift` changed (no result where `end` is `nil`).
    private func printed(
        start: TimeInterval,
        end: TimeInterval?,
        failed: Bool = false,
        change: (StopGateFixture) throws -> Void = StopGateBashEditTests.change
    ) async throws -> String {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture, change)
        var lines = [StopGateFixture.bash("t1", command: Self.sed, cwd: fixture.repo.path, at: now.addingTimeInterval(start))]
        if let end {
            lines.append(StopGateFixture.result("t1", failed: failed, at: now.addingTimeInterval(end)))
        }
        return try await fixture.hook(["transcript_path": fixture.transcript(lines)])
    }

    @Test
    func aBashCallWhoseSpanCoversASwiftChangeBlocks() async throws {
        let reason = try #require(try await StopGateFixture.blockReason(of: printed(start: 0, end: 5)))

        #expect(reason.contains("1 Swift file (Depot.swift)"))
    }

    @Test
    func aBashCallThatEndedBeforeTheChangeDoesNotBlock() async throws {
        #expect(try await printed(start: -120, end: -60).isEmpty)
    }

    @Test
    func aFailedBashCallWhoseSpanCoversTheChangeStillBlocks() async throws {
        let reason = try #require(try await StopGateFixture.blockReason(of: printed(start: 0, end: 5, failed: true)))

        #expect(reason.contains("1 Swift file (Depot.swift)"))
    }

    @Test
    func aBashCallWithNoResultDoesNotBlock() async throws {
        #expect(try await printed(start: 0, end: nil).isEmpty)
    }

    @Test
    func aGreenRunAfterTheCoveringCallAnswersIt() async throws {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture)
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: Self.sed, cwd: fixture.repo.path, at: now.addingTimeInterval(0)),
            StopGateFixture.result("t1", at: now.addingTimeInterval(5)),
            StopGateFixture.bash("t2", command: "cd \(fixture.repo.path) && swift-sure run -- swift build 2>&1", cwd: fixture.repo.path, at: now.addingTimeInterval(6)),
            StopGateFixture.result("t2", at: now.addingTimeInterval(7)),
        ])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    @Test
    func aGitIgnoredSwiftFileChangedInTheSpanDoesNotBlock() async throws {
        let printed = try await printed(start: 0, end: 5) { fixture in
            try "Ignored/\n".write(to: fixture.repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            _ = try fixture.file("Ignored/Skip.swift")
        }

        #expect(printed.isEmpty)
    }

    @Test
    func aValidatingRunThatFailedDoesNotSpan() async throws {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture)
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: "cd \(fixture.repo.path) && swift-sure run -- swift build 2>&1", cwd: fixture.repo.path, at: now.addingTimeInterval(0)),
            StopGateFixture.result("t1", failed: true, at: now.addingTimeInterval(5)),
        ])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    /// A call running `swift-sure run`, validating or not, is the tool's own and does not span, whatever else its line holds.
    @Test(arguments: [false, true])
    func aPipedRunDuringWhichTheFileChangedDoesNotSpan(failed: Bool) async throws {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture)
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: "swift-sure run -- swift test 2>&1 | tail -20", cwd: fixture.repo.path, at: now.addingTimeInterval(0)),
            StopGateFixture.result("t1", failed: failed, at: now.addingTimeInterval(5)),
        ])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    @Test
    func aBuildThroughAnotherServerAfterTheSpanClearsTheEdit() async throws {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture)
        let build: [String: Any] = [
            "type": "tool_use", "id": "t2", "name": "mcp__gizmo__build_project",
            "input": ["projectPath": fixture.repo.appendingPathComponent("Depot.xcodeproj").path, "scheme": "Depot"],
        ]
        var call: [String: Any] = ["type": "assistant", "isSidechain": false, "message": ["role": "assistant", "content": [build]]]
        call["timestamp"] = StopGateFixture.stamp(now.addingTimeInterval(6))
        let answer: [String: Any] = ["type": "tool_result", "tool_use_id": "t2", "is_error": false, "content": "Compiling Depot\n** BUILD SUCCEEDED **"]
        var reply: [String: Any] = ["type": "user", "isSidechain": false, "message": ["role": "user", "content": [answer]]]
        reply["timestamp"] = StopGateFixture.stamp(now.addingTimeInterval(7))
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: Self.sed, cwd: fixture.repo.path, at: now.addingTimeInterval(0)),
            StopGateFixture.result("t1", at: now.addingTimeInterval(5)),
            call,
            reply,
        ])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    /// The edit is dated when the span holding the change ended, not when a later span that changed nothing did, so a run that began between the two follows the edit.
    @Test
    func aLaterSpanThatChangedNothingDoesNotDateTheEdit() async throws {
        let fixture = try StopGateFixture()
        let now = try Self.settle(fixture)
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: Self.sed, cwd: fixture.repo.path, at: now.addingTimeInterval(0)),
            StopGateFixture.result("t1", at: now.addingTimeInterval(5)),
            StopGateFixture.bash("t2", command: "ls", cwd: fixture.repo.path, at: now.addingTimeInterval(7)),
            StopGateFixture.result("t2", at: now.addingTimeInterval(8)),
        ])
        let directory = RunProgressPaths.directory(in: fixture.repo, writesUnder: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var snapshot = try RunProgressSnapshot(
            runId: "20261010T100000000Z-0a1b2c3d",
            pid: getpid(),
            repoRoot: fixture.repo.path,
            startedAt: now.addingTimeInterval(6),
            command: "swift test",
            tree: #require(TreeKey.of(repositoryRoot: fixture.repo)).value
        )
        snapshot.phase = .testing
        snapshot.updatedAt = now.addingTimeInterval(9)
        try snapshot.encoded().write(to: RunProgressPaths.file(runId: snapshot.runId, in: directory))

        #expect(await fixture.hook(["transcript_path": transcript], now: now.addingTimeInterval(10)).isEmpty)
    }
}
