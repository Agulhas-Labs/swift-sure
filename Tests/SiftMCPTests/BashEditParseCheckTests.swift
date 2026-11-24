//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftCore
@testable import SiftMCP
import Testing

/// The `PostToolUse` hook parse-checks the Swift files a `Bash` call changed, once per content, and says nothing for a file changed before the call began.
@Suite(.temporaryDirectories)
struct BashEditParseCheckTests {
    @Test func aFileBrokenAfterTheCallBeganIsBlockedWithEachErrorPlaced() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        let reason = try await BashFixture.reason(of: fixture.hook())

        #expect(reason?.contains("Sources/App/Depot.swift:3:21 expected expression after operator") == true)
        #expect(reason?.contains("Sources/App/Depot.swift:4:6 expected '}' to end struct") == true)
    }

    @Test func aFileLeftCleanIsSilent() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", "struct Depot {}\n")

        #expect(await fixture.hook().isEmpty)
    }

    @Test func aBrokenFileChangedBeforeTheCallBeganIsNotThisCallsEdit() async throws {
        let fixture = try BashFixture(at: 5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        #expect(await fixture.hook().isEmpty)
    }

    @Test func aCallWithNoTranscriptEntryChecksNothing() async throws {
        let fixture = try BashFixture(at: -5, toolUseID: "other")
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        #expect(await fixture.hook().isEmpty)
    }

    @Test func aGitIgnoredBrokenFileIsNotChecked() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write(".gitignore", "Ignored/\n")
        try fixture.write("Ignored/Stray.swift", BashFixture.broken)

        #expect(await fixture.hook().isEmpty)
    }

    @Test func aBrokenNewUntrackedFileIsChecked() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Fresh.swift", BashFixture.broken)

        let reason = try await BashFixture.reason(of: fixture.hook())

        #expect(reason?.contains("Sources/App/Fresh.swift:3:21") == true)
    }

    @Test func runOnlyModeChecksNothing() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        #expect(await fixture.hook(withShellEdits: false).isEmpty)
    }

    @Test func theSameBrokenContentAfterASecondCallIsBlockedOnce() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        #expect(try await BashFixture.reason(of: fixture.hook()) != nil)
        #expect(await fixture.hook().isEmpty)
    }

    @Test func everyFailingFileIsNamedInTheOneBlock() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)
        try fixture.write("Sources/App/Other.swift", BashFixture.broken)

        let reason = try await BashFixture.reason(of: fixture.hook())

        #expect(reason?.contains("Sources/App/Depot.swift:3:21") == true)
        #expect(reason?.contains("Sources/App/Other.swift:3:21") == true)
        #expect(reason?.contains("The edit left Sources/App/Other.swift unparseable") == true)
    }

    @Test func aSubagentCallIsFoundInTheSubagentsOwnTranscript() async throws {
        let fixture = try BashFixture(at: -5, subagent: "abc")
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        let reason = try await BashFixture.reason(of: fixture.hook(extra: ["agent_id": "abc"]))

        #expect(reason?.contains("Sources/App/Depot.swift:3:21") == true)
    }

    @Test func aSlowCheckLeavesTheDiagnosticsNoteItsShareOfTheBudget() async throws {
        let fixture = try BashFixture(at: -5)
        for index in 0 ..< 8 {
            try fixture.write("Sources/App/Clean\(index).swift", "struct Clean\(index) {}\n")
        }
        let slow: BashEditParseCheck.FileParse = { _, _ in
            Thread.sleep(forTimeInterval: 0.3)
            return nil
        }

        let printed = await fixture.hook(timeBudget: 1.5, stdout: "Sources/App/Depot.swift:2:5: error: boom\n", parse: slow)

        #expect(try BashFixture.reason(of: printed) == nil)
        #expect(printed.contains("Depot.swift"))
    }

    @Test func aFileFoundBrokenBeforeTheCheckRanOutStillBlocks() throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)
        try fixture.write("Sources/App/Other.swift", "struct Other {}\n")
        try fixture.write("Sources/App/Third.swift", "struct Third {}\n")
        let ranOut = ResultBox<Bool>()
        let parsed = ResultBox<[String]>()
        parsed.value = []
        let parse: BashEditParseCheck.FileParse = { file, root in
            parsed.value = (parsed.value ?? []) + [(file as NSString).lastPathComponent]
            guard file.hasSuffix("Depot.swift") else { return nil }
            ranOut.value = true
            return BashEditParseCheck.standardParse(file, root)
        }
        let result = ResultBox<[BashEditParseCheck.Failure]>()
        result.value = []
        let deadline = Date()

        BashEditParseCheck.failures(
            transcript: fixture.transcript.path, toolUseID: "t9", cwd: fixture.repo.path, deadline: deadline, parse: parse, into: result,
            now: { ranOut.value == true ? deadline : .distantPast }
        )

        #expect(result.value?.map { ($0.file as NSString).lastPathComponent } == ["Depot.swift"])
        #expect(result.value?.first?.check.reason.contains("Sources/App/Depot.swift:3:21") == true)
        #expect(parsed.value?.contains("Other.swift") == false)
        #expect(parsed.value?.contains("Third.swift") == false)
    }

    @Test func aFailedCallLeavingABrokenFileIsBlocked() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        let reason = try await BashFixture.reason(of: fixture.failure())

        #expect(reason?.contains("Sources/App/Depot.swift:3:21") == true)
    }

    @Test func aFailedCallInRunOnlyModeChecksNothingBeyondTheNote() async throws {
        let fixture = try BashFixture(at: -5)
        try fixture.write("Sources/App/Depot.swift", BashFixture.broken)

        #expect(await fixture.failure(withShellEdits: false).isEmpty)
    }

    @Test func runOnlyModeTurnsTheBashParseCheckOff() {
        #expect(PostToolUseCommand.parsesBashCalls(runOnly: false))
        #expect(!PostToolUseCommand.parsesBashCalls(runOnly: true))
    }
}

private extension BashEditParseCheckTests {
    /// A committed repository, a transcript holding one `Bash` `tool_use` that began `offset` seconds from now, and the hook's marks.
    struct BashFixture {
        static var broken: String {
            "struct Depot {\n    func go() {\n        let x = (1 +\n    }\n"
        }

        let repo: URL
        let transcript: URL
        let marks: HookMarks

        init(at offset: TimeInterval, toolUseID: String = "t9", subagent: String? = nil) throws {
            repo = try MCPTestRepo.make(declaring: "Depot")
            marks = try HookMarks(directory: TemporaryDirectory.make("bash-marks"))
            transcript = try TemporaryDirectory.make("bash-transcript").appendingPathComponent("session.jsonl")
            let stamp = ISO8601DateFormatter.string(from: Date(timeIntervalSinceNow: offset), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
            let line = """
            {"type":"assistant","timestamp":"\(stamp)","message":{"content":[{"type":"tool_use","id":"\(toolUseID)","name":"Bash","input":{"command":"sed -i '' s/a/b/ x"}}]}}
            """
            guard let subagent else {
                try (line + "\n").write(to: transcript, atomically: true, encoding: .utf8)
                return
            }
            try "{\"type\":\"user\"}\n".write(to: transcript, atomically: true, encoding: .utf8)
            let own = transcript.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
            try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
            try (line + "\n").write(to: own.appendingPathComponent("agent-\(subagent).jsonl"), atomically: true, encoding: .utf8)
        }

        func write(_ relative: String, _ source: String) throws {
            let url = repo.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }

        private func payload(stdout: String, extra: [String: Any]) -> [String: Any] {
            var payload: [String: Any] = [
                "tool_name": "Bash", "tool_use_id": "t9", "tool_input": ["command": "sed"],
                "tool_response": ["stdout": stdout, "stderr": ""], "session_id": "s1",
                "transcript_path": transcript.path, "cwd": repo.path,
            ]
            payload.merge(extra) { _, new in new }
            return payload
        }

        /// What the hook printed for the transcript's `Bash` call, run off the concurrency pool as the hook's main thread would.
        func hook(
            withShellEdits: Bool = true, timeBudget: TimeInterval = InPlaceAnswerTests.roomy, stdout: String = "",
            extra: [String: Any] = [:], parse: @escaping BashEditParseCheck.FileParse = BashEditParseCheck.standardParse
        ) async -> String {
            let recorded = RecordedOutput()
            let (marks, sent) = (marks, PayloadBox(payload(stdout: stdout, extra: extra)))
            await InPlaceAnswerTests.onItsOwnThread {
                PostToolUseCommand.answer(
                    to: sent.payload, output: recorded.output, marks: marks,
                    timeBudget: timeBudget, withShellEdits: withShellEdits, parse: parse
                )
            }
            return recorded.printed
        }

        /// What the hook printed when the transcript's `Bash` call failed.
        func failure(withShellEdits: Bool = true) async -> String {
            let recorded = RecordedOutput()
            var failed = payload(stdout: "", extra: ["hook_event_name": "PostToolUseFailure", "error": "Exit code 1\nboom"])
            failed["tool_response"] = nil
            let (marks, sent) = (marks, PayloadBox(failed))
            await InPlaceAnswerTests.onItsOwnThread {
                PostToolUseCommand.answerFailure(to: sent.payload, output: recorded.output, marks: marks, withShellEdits: withShellEdits, timeBudget: InPlaceAnswerTests.roomy)
            }
            return recorded.printed
        }

        static func reason(of printed: String) throws -> String? {
            guard !printed.isEmpty else { return nil }
            let object = try JSONSerialization.jsonObject(with: Data(printed.utf8)) as? [String: Any]
            guard object?["decision"] as? String == "block" else { return nil }
            return object?["reason"] as? String
        }
    }

    /// A hook payload carried onto the hook's own thread; never mutated once made.
    final class PayloadBox: @unchecked Sendable {
        let payload: [String: Any]

        init(_ payload: [String: Any]) {
            self.payload = payload
        }
    }
}
