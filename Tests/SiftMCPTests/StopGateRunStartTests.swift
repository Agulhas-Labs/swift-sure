//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A build or test still going in the checkout answers the Stop gate by when it started: after the context's last edit it lets the stop through whatever tree it names, before it the block says to wait, and past the ceiling on its start it is no live run.
@Suite(.temporaryDirectories)
struct StopGateRunStartTests {
    private static let otherTree = String(repeating: "b", count: 40)
    /// The instant each test judges at, injected, a minute back from the wall clock.
    private let now = Date().addingTimeInterval(-60)

    /// A child process of the test's own, alive until `body` returns, then killed and reaped.
    ///
    /// Spawned and reaped by hand: `Process.waitUntilExit()`, reached after the `await` on another thread than the launch, can miss the exit and wait forever.
    private func withLiveChild(sourceLocation: SourceLocation = #_sourceLocation, _ body: (Int32) async throws -> Void) async throws {
        let spawned = IsolatedSpawn.start("/bin/sleep", arguments: ["/bin/sleep", "600"])
        try #require(spawned.status == 0, sourceLocation: sourceLocation)
        let pid = spawned.pid
        defer {
            kill(pid, SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
        try await body(pid)
    }

    /// The edit, its result landing at the given instant.
    private func transcript(_ fixture: StopGateFixture, editedAt: Date) throws -> String {
        var result = StopGateFixture.result("t1")
        result["timestamp"] = ISO8601DateFormatter().string(from: editedAt)
        return try fixture.transcript([StopGateFixture.edit("t1", path: fixture.depot), result])
    }

    /// Writes the progress file of a `swift test` run of another tree by `pid`, started at `startedAt` and heard from at `now`.
    private func run(in fixture: StopGateFixture, pid: Int32, startedAt: Date, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let directory = RunProgressPaths.directory(in: fixture.repo, writesUnder: nil)
        #expect(directory.path.hasPrefix(fixture.repo.path), sourceLocation: sourceLocation)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = "20261012T100000000Z-0c1d2e3f"
        var snapshot = RunProgressSnapshot(runId: id, pid: pid, repoRoot: fixture.repo.path, startedAt: startedAt, command: "swift test", tree: Self.otherTree)
        snapshot.phase = .testing
        snapshot.updatedAt = now
        try snapshot.encoded().write(to: RunProgressPaths.file(runId: id, in: directory))
    }

    /// The case: a runner was handed the tree after the last edit and is testing it; its tree key is not the one judged, and the stop still passes, claiming nothing.
    @Test
    func aLiveRunStartedAfterTheLastEditLetsTheStopThrough() async throws {
        let fixture = try StopGateFixture()
        let transcript = try transcript(fixture, editedAt: now.addingTimeInterval(-600))
        try await withLiveChild { pid in
            try run(in: fixture, pid: pid, startedAt: now.addingTimeInterval(-300))

            #expect(await fixture.hook(["transcript_path": transcript], now: now).isEmpty)
        }
    }

    /// Started before the last edit, the run says nothing of the tree as it stands: the stop is blocked, with the advice to wait for it.
    @Test
    func aLiveRunStartedBeforeTheLastEditBlocksWithTheAdviceToWait() async throws {
        let fixture = try StopGateFixture()
        let transcript = try transcript(fixture, editedAt: now.addingTimeInterval(-300))
        try await withLiveChild { pid in
            try run(in: fixture, pid: pid, startedAt: now.addingTimeInterval(-600))

            let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript], now: now)))

            #expect(reason.contains("A `swift-sure run` of an earlier tree is in progress"))
        }
    }

    /// A run that started longer ago than the ceiling is no live run, though its pid answers and its heartbeat is fresh.
    @Test
    func aRunStartedPastTheCeilingIsNoLiveRun() async throws {
        let fixture = try StopGateFixture()
        let started = now.addingTimeInterval(-RunProgressSnapshot.processCeiling - 60)
        let transcript = try transcript(fixture, editedAt: started.addingTimeInterval(-60))
        try await withLiveChild { pid in
            try run(in: fixture, pid: pid, startedAt: started)

            let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript], now: now)))

            #expect(reason.contains("Run `(cd "))
            #expect(!reason.contains("in progress"))
        }
    }

    /// A pid whose process started after the run did is one the system has given to another process since the run ended: no live run, though it answers a signal.
    @Test
    func aPidHeldByAProcessStartedAfterTheRunIsNoLiveRun() async throws {
        let fixture = try StopGateFixture()
        let started = now.addingTimeInterval(-300)
        let transcript = try transcript(fixture, editedAt: now.addingTimeInterval(-600))
        try await withLiveChild { pid in
            try run(in: fixture, pid: pid, startedAt: started)

            let reused = await fixture.hook(["transcript_path": transcript], now: now) { _ in started.addingTimeInterval(120) }
            let reason = try #require(try StopGateFixture.blockReason(of: reused))

            #expect(reason.contains("Run `(cd "))
            #expect(!reason.contains("in progress"))
        }
    }

    /// The run is judged against the last edit in its own repository: a later edit in another repository, which a build there cleared, does not make it a run of an earlier tree.
    @Test
    func aRunIsJudgedAgainstTheLastEditInItsOwnRepository() async throws {
        let fixture = try StopGateFixture()
        let other = try MCPTestRepo.make(declaring: "Gauge")
        var depotEdited = StopGateFixture.result("t1")
        depotEdited["timestamp"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        var gaugeEdited = StopGateFixture.result("t2")
        gaugeEdited["timestamp"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(-100))
        let build: [String: Any] = ["type": "tool_use", "id": "t3", "name": "mcp__gizmo__build_project", "input": ["workspacePath": other.appendingPathComponent("Gauge.xcworkspace").path]]
        let built: [String: Any] = ["type": "tool_result", "tool_use_id": "t3", "is_error": false, "content": "** BUILD SUCCEEDED **"]
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            depotEdited,
            StopGateFixture.edit("t2", path: other.appendingPathComponent("Sources/App/Gauge.swift").path),
            gaugeEdited,
            ["type": "assistant", "isSidechain": false, "message": ["role": "assistant", "content": [build]]],
            ["type": "user", "isSidechain": false, "message": ["role": "user", "content": [built]]],
        ])
        try await withLiveChild { pid in
            try run(in: fixture, pid: pid, startedAt: now.addingTimeInterval(-300))

            #expect(await fixture.hook(["transcript_path": transcript], now: now).isEmpty)
        }
    }
}
