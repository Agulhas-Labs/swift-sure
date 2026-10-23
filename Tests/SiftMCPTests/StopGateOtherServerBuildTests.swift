//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A build made through another MCP server's tool answers the Stop gate only where its result carries a success line, no failure line anywhere, and tests run where it is a test run, and only for the repository it names.
@Suite(.temporaryDirectories)
struct StopGateOtherServerBuildTests {
    private static var swiftTestingOnly: String {
        """
        Building for debugging...
        Build complete! (1.20s)
        Test Suite 'All tests' passed at 2026-10-12 10:00:00.000.
        Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
        ✔ Test run with 12 tests in 3 suites passed after 0.015 seconds.
        """
    }

    private static func call(_ id: String, tool: String = "mcp__gizmo__build_project", input: [String: Any]) -> [String: Any] {
        let use: [String: Any] = ["type": "tool_use", "id": id, "name": tool, "input": input]
        return ["type": "assistant", "isSidechain": false, "message": ["role": "assistant", "content": [use]]]
    }

    private static func result(_ id: String, text: String, failed: Bool = false, asBlocks: Bool = false) -> [String: Any] {
        let content: Any = asBlocks ? [["type": "text", "text": text]] : text
        let block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "is_error": failed, "content": content]
        return ["type": "user", "isSidechain": false, "message": ["role": "user", "content": [block]]]
    }

    /// The edit, then one call to `tool` naming the fixture's project, answered with `text`.
    private func transcript(_ fixture: StopGateFixture, tool: String = "mcp__gizmo__build_project", text: String, failed: Bool = false, asBlocks: Bool = false) throws -> String {
        try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", tool: tool, input: ["projectPath": fixture.repo.appendingPathComponent("Depot.xcodeproj").path, "scheme": "Depot"]),
            Self.result("t2", text: text, failed: failed, asBlocks: asBlocks),
        ])
    }

    /// Results that clear, by a name the runner prints in place of the text, whose lines would read as the run's own.
    private static let green = [
        "xcodebuild build": "Compiling Depot\n** BUILD SUCCEEDED **",
        "swift build": "[3/3] Linking Depot\nBuild complete! (3.10s)",
        "xcodebuild test": "Test Suite 'All tests' passed.\nExecuted 5 tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds\n** TEST SUCCEEDED **",
    ]

    /// Test runs that executed nothing, by name.
    private static let empty = [
        "XCTest zero": "Build complete! (1.20s)\nExecuted 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds",
        "both zero": "Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds\n✔ Test run with 0 tests passed after 0.001 seconds.",
        "no count": "** TEST SUCCEEDED **",
    ]

    /// Results with a failure line, by name.
    private static let red = [
        "build failed": "** BUILD FAILED **",
        "error before success": "Depot.swift:3:1: error: cannot find 'x' in scope\n** BUILD SUCCEEDED **",
        "test failed before success": "** TEST FAILED **\n** BUILD SUCCEEDED **",
        "Swift Testing failed": "✘ Test run with 3 tests in 1 suite failed after 0.1 seconds with 1 issue.\nBuild complete! (1.00s)",
        "mixed frameworks": "Executed 5 tests, with 2 failures (0 unexpected) in 0.1 (0.1) seconds\n✔ Test run with 4 tests passed after 0.1 seconds.",
        "one failure": "Executed 1 test, with 1 failure (0 unexpected) in 0.1 (0.1) seconds\n** TEST SUCCEEDED **",
    ]

    @Test(arguments: green.keys.sorted())
    func aSuccessLineWithNoFailureLineClearsTheEdit(name: String) async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.green[name])

        #expect(try await fixture.hook(["transcript_path": transcript(fixture, text: text)]).isEmpty)
        #expect(try await fixture.hook(["transcript_path": transcript(fixture, tool: "mcp__gizmo__buildOnSimulator", text: text, asBlocks: true)]).isEmpty)
    }

    /// A tool named for tests is a test run whatever its text shows: a count of tests run clears it.
    @Test
    func aTestToolWhoseResultCountsTestsRunClearsTheEdit() async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.green["xcodebuild test"])

        #expect(try await fixture.hook(["transcript_path": transcript(fixture, tool: "mcp__gizmo__testOnSimulator", text: text, asBlocks: true)]).isEmpty)
    }

    /// A tool named for tests whose result holds only a build's success line (the test output trimmed, dropped or timed out) does not clear.
    @Test(arguments: ["xcodebuild build", "swift build"], ["mcp__gizmo__test_package", "mcp__gizmo__build_and_run_tests", "mcp__gizmo__buildAndRunTests", "mcp__gizmo__build_with_testing"])
    func aTestToolWhoseResultCarriesOnlyABuildLineDoesNotClear(name: String, tool: String) async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.green[name])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript(fixture, tool: tool, text: text)])))

        #expect(reason.contains("Run `(cd "))
    }

    /// A tool named for tests in the plural is a test run, and clears where its result shows tests run and passed.
    @Test
    func aToolNamedForTestsInThePluralClearsOnATestPass() async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.green["xcodebuild test"])

        #expect(try await fixture.hook(["transcript_path": transcript(fixture, tool: "mcp__gizmo__run_tests", text: text)]).isEmpty)
    }

    /// A result too large to keep inline, which the harness stands in for with a preview of its head, is never read as green, whatever the preview shows.
    @Test
    func aResultTheHarnessPutAsideDoesNotClear() async throws {
        let fixture = try StopGateFixture()
        let preview = "<persisted-output>\nOutput too large (40.8KB). Full output saved to: /x/tool-results/t2.txt\n\nPreview (first 2KB):\nCompiling Depot\n** BUILD SUCCEEDED **\n</persisted-output>"

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript(fixture, text: preview)])))

        #expect(reason.contains("Run `(cd "))
    }

    /// A result holding any block that is not text says nothing green, since what that block shows cannot be read.
    @Test
    func aResultWithABlockThatIsNotTextDoesNotClear() async throws {
        let fixture = try StopGateFixture()
        let blocks: [[String: Any]] = [["type": "text", "text": "** BUILD SUCCEEDED **"], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": ""]]]
        let result: [String: Any] = ["type": "tool_result", "tool_use_id": "t2", "is_error": false, "content": blocks]
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", input: ["projectPath": fixture.repo.appendingPathComponent("Depot.xcodeproj").path]),
            ["type": "user", "isSidechain": false, "message": ["role": "user", "content": [result]]],
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("Run `(cd "))
    }

    /// `swift test` over Swift Testing alone prints XCTest's zero summary before the Swift Testing pass: the zero line is neither failure nor pass, and the Swift Testing count decides.
    @Test
    func aSwiftTestingOnlyPassBesideXCTestsZeroLineClearsTheEdit() async throws {
        let fixture = try StopGateFixture()

        #expect(try await fixture.hook(["transcript_path": transcript(fixture, text: Self.swiftTestingOnly)]).isEmpty)
    }

    /// A run that executed nothing is no pass, whichever framework said so.
    @Test(arguments: empty.keys.sorted())
    func aTestRunThatExecutedNoTestsDoesNotClear(name: String) async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.empty[name])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript(fixture, text: text)])))

        #expect(reason.contains("1 Swift file (Depot.swift)"))
    }

    /// A failure line anywhere outweighs a success line, the last line included, and mixed frameworks are read by every count, not one.
    @Test(arguments: red.keys.sorted())
    func aFailureLineAnywhereDoesNotClear(name: String) async throws {
        let fixture = try StopGateFixture()
        let text = try #require(Self.red[name])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript(fixture, text: text)])))

        #expect(reason.contains("Run `(cd "))
        #expect(!reason.contains("carries no success line"))
    }

    /// A result marked an error says nothing green, whatever its text.
    @Test
    func anErrorResultDoesNotClear() async throws {
        let fixture = try StopGateFixture()

        #expect(try await !fixture.hook(["transcript_path": transcript(fixture, text: "** BUILD SUCCEEDED **", failed: true)]).isEmpty)
    }

    /// A tool that reads a log, a result, a status or a history, or lists builds, can quote an earlier success, plurals included; a word that only contains `test` is no test, and this server's own tools are no build.
    @Test(arguments: [
        "mcp__gizmo__get_build_log",
        "mcp__gizmo__test_results",
        "mcp__gizmo__build_logs",
        "mcp__gizmo__build_status",
        "mcp__gizmo__last_build",
        "mcp__gizmo__latest_build",
        "mcp__gizmo__previous_build",
        "mcp__gizmo__build_history",
        "mcp__gizmo__recent_test",
        "mcp__gizmo__readTestResult",
        "mcp__gizmo__show-build-settings",
        "mcp__gizmo__list_tests",
        "mcp__gizmo__latest_snapshot",
        "mcp__gizmo__rebuild",
        ProductName.current.toolPrefix + "build_project",
    ])
    func aToolThatIsNoBuildClearsNothing(tool: String) async throws {
        let fixture = try StopGateFixture()

        let text = try #require(Self.green["xcodebuild test"])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript(fixture, tool: tool, text: text)])))

        #expect(reason.contains("Run `(cd "))
    }

    /// A build naming only paths outside every repository built an unrelated project: it clears nothing, though the context edited a single repository.
    @Test
    func aBuildNamingOnlyPathsOutsideEveryRepositoryClearsNothing() async throws {
        let fixture = try StopGateFixture()
        let scratch = fixture.transcripts.appendingPathComponent("Scratch/Demo.xcodeproj").path
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", input: ["projectPath": scratch, "derivedDataPath": "/tmp/dd"]),
            Self.result("t2", text: "** BUILD SUCCEEDED **"),
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("1 Swift file (Depot.swift)"))
    }

    /// A build with no success line that named only a path outside every repository says nothing of this one, so the block does not name it.
    @Test
    func aSilentBuildOfAnotherProjectIsNotNamedInTheBlock() async throws {
        let fixture = try StopGateFixture()
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", input: ["projectPath": fixture.transcripts.appendingPathComponent("Scratch/Demo.xcodeproj").path]),
            Self.result("t2", text: "Build queued."),
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("Run `(cd "))
        #expect(!reason.contains("carries no success line"))
    }

    /// A green build of another repository leaves this one's edits standing, though they are the only edits the context made.
    @Test
    func aBuildNamingAnotherRepositoryClearsNothingHere() async throws {
        let fixture = try StopGateFixture()
        let other = try MCPTestRepo.make(declaring: "Gauge")
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", input: ["workspacePath": other.appendingPathComponent("Gauge.xcworkspace").path]),
            Self.result("t2", text: "** BUILD SUCCEEDED **"),
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("1 Swift file (Depot.swift)"))
    }

    /// Edits in two repositories: a build naming one clears that one's and leaves the other's standing; a build naming no path clears neither.
    @Test
    func aBuildClearsOnlyTheRepositoryItNames() throws {
        let fixture = try StopGateFixture()
        let other = try MCPTestRepo.make(declaring: "Gauge")
        let gauge = other.appendingPathComponent("Sources/App/Gauge.swift").path
        let edits = [
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            StopGateFixture.edit("t2", path: gauge),
            StopGateFixture.result("t2"),
        ]
        let named = try fixture.transcript(edits + [
            Self.call("t3", input: ["cwd": fixture.repo.path]),
            Self.result("t3", text: "** BUILD SUCCEEDED **"),
        ], named: "named")
        let unnamed = try fixture.transcript(edits + [
            Self.call("t3", input: ["scheme": "Depot"]),
            Self.result("t3", text: "** BUILD SUCCEEDED **"),
        ], named: "unnamed")

        let standing = { (transcript: String) in
            BuildInputEditsSinceGreenRun.files(inTranscript: URL(fileURLWithPath: transcript), skippingSidechains: true)?.map { URL(fileURLWithPath: $0).lastPathComponent }
        }

        #expect(standing(named) == ["Gauge.swift"])
        #expect(standing(unnamed) == ["Depot.swift", "Gauge.swift"])
    }

    /// Where the context edited a single repository, a green build naming no path clears it; an edit after the build stands.
    @Test
    func aBuildNamingNoPathClearsTheOneRepositoryEditedButNotALaterEdit() async throws {
        let fixture = try StopGateFixture()
        let before = [
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", input: ["scheme": "Depot"]),
            Self.result("t2", text: "** BUILD SUCCEEDED **"),
        ]
        let cleared = try fixture.transcript(before, named: "cleared")
        let editedAfter = try fixture.transcript(before + [StopGateFixture.edit("t3", path: fixture.depot), StopGateFixture.result("t3")], named: "after")

        #expect(await fixture.hook(["transcript_path": cleared]).isEmpty)
        #expect(await !fixture.hook(["transcript_path": editedAfter]).isEmpty)
    }

    /// A build that ran after the last edit and answered with no success line at all is named in the block, the most recent one.
    @Test
    func aBuildWhoseResultCarriesNoSuccessLineIsNamedInTheBlock() async throws {
        let fixture = try StopGateFixture()
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.depot),
            StopGateFixture.result("t1"),
            Self.call("t2", tool: "mcp__widget__test_all", input: ["scheme": "Depot"]),
            Self.result("t2", text: "Started."),
            Self.call("t3", input: ["scheme": "Depot"]),
            Self.result("t3", text: "Build queued."),
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains(
            "as it stands; a build ran through gizmo build_project after the last edit, but its result carries no success line. Run `(cd "
        ))
    }
}
