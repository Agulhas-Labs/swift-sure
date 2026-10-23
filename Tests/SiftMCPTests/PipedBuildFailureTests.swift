//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftMCP
import Testing

/// A piped build or test whose output shows a failure is named after it ran: one line, in the post-tool answer, naming the `swift-sure run` call.
@Suite(.temporaryDirectories)
struct PipedBuildFailureTests {
    /// The CPU time the calling thread has used so far, in seconds: time spent waiting for a core is not counted, so a bound on the difference holds on a loaded machine.
    private static func cpuSecondsOfThisThread() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }

    /// The last `count` lines of a captured run under `Tests/SiftCoreTests/Fixtures/RunOutput/`, or all of it where `count` is `nil`.
    private static func fixture(_ name: String, tail count: Int? = nil) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SiftCoreTests/Fixtures/RunOutput")
        let text = try String(contentsOf: directory.appendingPathComponent("\(name).txt"), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(count ?? lines.count).joined(separator: "\n")
    }

    private static func tail(_ command: String, over output: String) -> String? {
        PipedBuildFailure.note(for: command, output: output)
    }

    private static func note(naming call: String, label: String) -> String {
        "swift-sure: this piped \(label) failed. `\(call)` lists each failure once by signature and keeps the full log under .swift-sure/runs/."
    }

    @Test func aFailingPipedSwiftBuildNamesTheWrappedBuild() throws {
        let output = try Self.fixture("swift-build-failure", tail: 15)

        #expect(Self.tail("swift build 2>&1 | tail -3", over: output) == Self.note(naming: "swift-sure run -- swift build", label: "build"))
    }

    @Test func aFailingPipedTestRunKeepsTheDirectoryChangeAndSaysTestRun() throws {
        let output = try Self.fixture("swift-test-fail", tail: 4)

        #expect(Self.tail("cd Kit && swift test 2>&1 | tail -20", over: output) == Self.note(naming: "cd Kit && swift-sure run -- swift test", label: "test run"))
    }

    @Test func aGroupAroundThePipelineStaysAroundTheNamedCall() throws {
        let output = try Self.fixture("swift-build-failure", tail: 15)

        #expect(Self.tail("(cd Kit && swift build 2>&1 | tail -3)", over: output) == Self.note(naming: "(cd Kit && swift-sure run -- swift build)", label: "build"))
    }

    @Test func aSetStatementIsLeftAsideAndKept() throws {
        let output = try Self.fixture("swift-build-colored-failure", tail: 3)

        #expect(Self.tail("set -o pipefail; swift build | tail -3", over: output) == Self.note(naming: "set -o pipefail; swift-sure run -- swift build", label: "build"))
    }

    @Test func theBuildsRedirectionsAndLaterStagesAreDropped() throws {
        let output = try Self.fixture("xcodebuild-test-failure", tail: 4)

        let note = try #require(Self.tail("xcodebuild test -scheme Gizmo -destination 'platform=macOS' 2>&1 | tee /tmp/x.log | tail -15", over: output))

        #expect(note == Self.note(naming: "swift-sure run -- xcodebuild test -scheme Gizmo -destination 'platform=macOS'", label: "test run"))
    }

    @Test func anXcodebuildThatRunsNoTestsIsABuild() throws {
        let output = try Self.fixture("xcodebuild-build-failure-dup")

        let note = try #require(Self.tail("xcodebuild build -scheme Gizmo | grep -E 'error|FAILED'", over: output))

        #expect(note.hasPrefix("swift-sure: this piped build failed."), "\(note)")
    }

    @Test func aColouredBuildFailureIsRead() throws {
        let output = try Self.fixture("swift-build-colored-failure", tail: 3)

        #expect(Self.tail("swift build 2>&1 | tail -3", over: output) != nil)
        #expect(Self.tail("xcodebuild build | tail -3", over: "\u{1B}[1;31m** BUILD FAILED **\u{1B}[0m") != nil)
    }

    @Test func eachFailureVerdictShowsAFailure() throws {
        for (name, count) in [("swift-test-crash-xc", 3), ("swift-test-xctest-only-failure", 14), ("swift-test-mixed-xctest-failure", nil), ("swift-test-fail", 4)] {
            let output = try Self.fixture(name, tail: count)

            #expect(Self.tail("swift test | tail -20", over: output) != nil, "\(name)")
        }

        #expect(Self.tail("swift test | tail -3", over: "\tExecuted 4 tests, with 1 failure (0 unexpected) in 0.1 (0.1) seconds") != nil)
        #expect(Self.tail("swift test | tail -3", over: "\tExecuted 4 tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds") == nil)
    }

    @Test func aPassingTailNamesNothing() throws {
        #expect(try Self.tail("swift build 2>&1 | tail -3", over: Self.fixture("swift-build-success", tail: 3)) == nil)
        #expect(try Self.tail("swift test 2>&1 | tail -3", over: Self.fixture("swift-test-pass", tail: 3)) == nil)
        #expect(try Self.tail("xcodebuild test -scheme Gizmo | tail -3", over: Self.fixture("xcodebuild-test-success", tail: 3)) == nil)
        #expect(try Self.tail("xcodebuild build -scheme Gizmo | tail -3", over: Self.fixture("xcodebuild-build-success", tail: 3)) == nil)
    }

    @Test func aBareErrorInAPassingFilteredRunIsNotAFailure() throws {
        let command = "xcodebuild test -scheme Gizmo | tee /tmp/x.log | grep -E \"error|FAILED\""
        let passing = try Self.fixture("xcodebuild-test-success", tail: 3) + "\nerror: expected"
        let failing = "error: expected\n** TEST FAILED **"

        #expect(Self.tail(command, over: passing) == nil)
        #expect(Self.tail(command, over: failing) != nil)
    }

    @Test func theCommandsOwnSuccessVerdictVetoesALocatedDiagnostic() {
        let located = "/Users/dev/Gizmo/Tests/GizmoTests.swift:6:9: error: expected"

        #expect(Self.tail("xcodebuild test -scheme Gizmo | grep error", over: "\(located)\n** TEST SUCCEEDED **") == nil)
        #expect(Self.tail("xcodebuild test -scheme Gizmo | grep error", over: "\(located)\n** BUILD SUCCEEDED **") != nil)
        #expect(Self.tail("swift test | tail -9", over: "\(located)\nTest run with 2 tests in 1 suite passed after 0.001 seconds.") == nil)
        #expect(Self.tail("swift test | tail -9", over: "\(located)\nTest run with 0 tests in 0 suites passed after 0.001 seconds.") != nil)
    }

    @Test func aBuildCompleteLineDoesNotVetoASwiftTestsLocatedXCTestError() throws {
        let kept = try Self.fixture("swift-test-xctest-only-failure").split(separator: "\n")
            .filter { $0.contains("Build complete!") || $0.contains(": error:") }.joined(separator: "\n")

        #expect(kept.contains("Build complete!") && kept.contains(": error:"))
        #expect(Self.tail("swift test | head -40", over: kept) != nil)
    }

    @Test func callsThatAreNotOnePipelineOfABuildNameNothing() throws {
        let output = try Self.fixture("swift-build-failure", tail: 15)
        let testOutput = try Self.fixture("swift-test-fail", tail: 4)

        #expect(Self.tail("swift build | tail -3 && swift test | tail -5", over: output + testOutput) == nil)
        #expect(Self.tail("swift build | tail -3; git push", over: output) == nil)
        #expect(Self.tail("swift test --filter Gizmo 2>&1 | cat", over: testOutput) == nil)
        #expect(Self.tail("swift-sure run -- swift build | tail -3", over: output) == nil)
        #expect(Self.tail("swift build > build.log 2>&1", over: output) == nil)
        #expect(Self.tail("swift build > build.log | tail -3", over: output) == nil)
        #expect(Self.tail("swift build", over: output) == nil)
        #expect(Self.tail("swiftlint lint --strict | tail -3", over: output) == nil)
        #expect(Self.tail("sh -c 'swift build | tail -3'", over: output) == nil)
        #expect(Self.tail("xcodebuild test-without-building -scheme Gizmo | tail -3", over: "** TEST EXECUTE FAILED **") == nil)
    }

    @Test func aSubshellThatDoesNotOpenWithCdIsRead() throws {
        let build = try Self.fixture("swift-build-linkerror", tail: 3)
        let test = try Self.fixture("swift-test-fail", tail: 20)

        #expect(Self.tail("(swift build 2>&1 | tail -3)", over: build) == Self.note(naming: "(swift-sure run -- swift build)", label: "build"))
        #expect(Self.tail("cd Kit && (swift test 2>&1 | tail -20)", over: test) == Self.note(naming: "cd Kit && (swift-sure run -- swift test)", label: "test run"))
    }

    @Test func argumentsAfterARedirectionAreKept() throws {
        let test = try Self.fixture("swift-test-fail", tail: 20)
        let build = try Self.fixture("swift-build-failure", tail: 15)

        #expect(Self.tail("swift test 2>&1 --filter Gizmo | tail -20", over: test) == Self.note(naming: "swift-sure run -- swift test --filter Gizmo", label: "test run"))
        #expect(Self.tail("swift build 2>/dev/null | tail -3", over: build) == Self.note(naming: "swift-sure run -- swift build", label: "build"))
        #expect(Self.tail("swift build -c release 2>&1 --product Gizmo | tail -3", over: build) == Self.note(naming: "swift-sure run -- swift build -c release --product Gizmo", label: "build"))
    }

    @Test func aLongOutputOfShortLinesIsReadQuicklyAndAPassedDeadlineReadsNothing() throws {
        let filler = String(repeating: "0123456789\n", count: 40000)
        let output = try filler + Self.fixture("swift-build-colored-failure", tail: 3)
        let started = Self.cpuSecondsOfThisThread()
        let named = PipedBuildFailure.note(for: "swift build 2>&1 | tail -3", output: output, deadline: .distantFuture)
        let spent = Self.cpuSecondsOfThisThread() - started

        #expect(named == Self.note(naming: "swift-sure run -- swift build", label: "build"))
        #expect(spent < 1)
        #expect(PipedBuildFailure.note(for: "swift build 2>&1 | tail -3", output: output, deadline: Date(timeIntervalSinceNow: -1)) == nil)
    }

    // MARK: - The hook's answer

    private static func context(of printed: String) throws -> String {
        try DiagnosticNoteTests.context(of: printed)
    }

    private func claudeAnswer(command: String, stdout: String, event: String = "PostToolUse", repo: String? = nil) throws -> String {
        let cwd = try repo ?? TemporaryDirectory.make("piped-cwd").path
        let marks = try ReuseNudgeMarks(directory: TemporaryDirectory.make("nudge-marks"))
        let recorded = RecordedOutput()
        PostToolUseCommand.answer(
            to: ["tool_name": "Bash", "tool_input": ["command": command], "tool_response": ["stdout": stdout, "stderr": ""], "session_id": "s1", "cwd": cwd, "hook_event_name": event],
            output: recorded.output,
            marks: marks
        )
        return recorded.printed
    }

    @Test func theClaudeAnswerCarriesTheNote() throws {
        let printed = try claudeAnswer(command: "swift build 2>&1 | tail -3", stdout: Self.fixture("swift-build-colored-failure", tail: 3))

        #expect(try Self.context(of: printed) == Self.note(naming: "swift-sure run -- swift build", label: "build"))
    }

    @Test func theNoteFollowsTheDiagnosticsNoteInOneAnswer() throws {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([DiagnosticNoteTests.producerPath: DiagnosticNoteTests.producer], to: repo)
        let stdout = "\(repo.path)/\(DiagnosticNoteTests.producerPath):6:25: error: cannot convert\nerror: Build failed"

        let printed = try claudeAnswer(command: "swift build 2>&1 | tail -3", stdout: stdout, repo: repo.path)

        let context = try Self.context(of: printed)

        #expect(context.hasPrefix(DiagnosticNoteTests.expected), "\(context)")
        #expect(context.hasSuffix("\n" + Self.note(naming: "swift-sure run -- swift build", label: "build")), "\(context)")
        #expect(printed.split(separator: "\n").count == 1)
    }

    @Test func aFailureEventPayloadCarriesTheNoteUnderItsOwnEventName() throws {
        let recorded = RecordedOutput()
        let cwd = try TemporaryDirectory.make("piped-failure").path
        let error = try "Exit code 1\n" + Self.fixture("swift-build-colored-failure", tail: 3)

        PostToolUseCommand.answerFailure(
            to: ["hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": ["command": "set -o pipefail; swift build | tail -3"], "error": error, "cwd": cwd, "session_id": "s1"],
            output: recorded.output
        )

        let object = try #require(JSONSerialization.jsonObject(with: Data(recorded.printed.utf8)) as? [String: Any])

        #expect((object["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String == "PostToolUseFailure")
        #expect(try Self.context(of: recorded.printed) == Self.note(naming: "set -o pipefail; swift-sure run -- swift build", label: "build"))
    }

    @Test func aFailureEventTheUserInterruptedGetsNoPipedNoteButKeepsTheDiagnosticsNote() throws {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([DiagnosticNoteTests.producerPath: DiagnosticNoteTests.producer], to: repo)
        let error = "Exit code 1\n\(repo.path)/\(DiagnosticNoteTests.producerPath):6:25: error: cannot convert\nerror: Build failed"
        func answer(interrupted: Bool) -> String {
            let recorded = RecordedOutput()
            PostToolUseCommand.answerFailure(
                to: ["hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": ["command": "swift build 2>&1 | tail -3"], "error": error, "cwd": repo.path, "session_id": "s1", "is_interrupt": interrupted],
                output: recorded.output
            )
            return recorded.printed
        }

        let ended = try Self.context(of: answer(interrupted: false))
        let interrupted = try Self.context(of: answer(interrupted: true))

        #expect(ended.hasSuffix(Self.note(naming: "swift-sure run -- swift build", label: "build")), "\(ended)")
        #expect(interrupted == DiagnosticNoteTests.expected, "\(interrupted)")
    }

    // MARK: - Cursor

    private func cursorPost(_ scene: CursorPreToolUseTests.Scene, command: String, text: String, interrupted: Bool? = nil) -> [String: Any] {
        var payload = CursorRewriteNoticeTests.post(scene)
        payload["tool_input"] = ["command": command, "cwd": "", "timeout": 30000]
        if let interrupted {
            payload["hook_event_name"] = "postToolUseFailure"
            payload["tool_output"] = nil
            payload["error_message"] = text
            payload["failure_type"] = "error"
            payload["is_interrupt"] = interrupted
        } else {
            payload["tool_output"] = String(bytes: (try? JSONSerialization.data(withJSONObject: ["output": text, "exitCode": 0])) ?? Data(), encoding: .utf8)
        }
        return payload
    }

    @Test func cursorsShellResultGetsTheNoteAsItsAdditionalContext() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let payload = cursorPost(scene, command: "xcodebuild test -scheme Gizmo 2>&1 | tail -15", text: "Testing failed:\n\n** TEST FAILED **\n")

        let run = try CursorRewriteNoticeTests.runPost(payload, in: scene)

        let context = try #require(CursorPreToolUseTests.object(run.printed)["additional_context"] as? String, "printed \(run.printed)")

        #expect(context == Self.note(naming: "swift-sure run -- xcodebuild test -scheme Gizmo", label: "test run"))
    }

    @Test func cursorsFailureEventCarriesTheNoteUnlessTheCallWasInterrupted() throws {
        let scene = try CursorPreToolUseTests.Scene()
        let command = "swift build 2>&1 | tail -3"
        let text = try Self.fixture("swift-build-colored-failure", tail: 3)

        let failed = try CursorRewriteNoticeTests.runPost(cursorPost(scene, command: command, text: text, interrupted: false), in: scene)
        let interrupted = try CursorRewriteNoticeTests.runPost(cursorPost(scene, command: command, text: text, interrupted: true), in: scene)

        #expect(failed.printed.contains("this piped build failed"), "printed \(failed.printed)")
        #expect(interrupted.printed.isEmpty, "printed \(interrupted.printed)")
    }
}
