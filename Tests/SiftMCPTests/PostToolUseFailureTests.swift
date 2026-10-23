//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import SiftMCP
import Testing

/// A call that fails reaches `post-tool-use` as a failure event: Claude Code's `PostToolUseFailure` for `Bash` and Cursor's `postToolUseFailure` for `Shell`, read as the call's output.
@Suite(.temporaryDirectories)
struct PostToolUseFailureTests {
    /// A Claude Code `PostToolUseFailure` payload as a probe recorded it: no `tool_response`, the output in `error` after an `Exit code` line.
    private static func claude(tool: String = "Bash", error: String, cwd: String) -> [String: Any] {
        [
            "hook_event_name": "PostToolUseFailure", "tool_name": tool, "tool_input": ["command": "swiftc Producer.swift"],
            "tool_use_id": "t1", "session_id": "s1", "cwd": cwd, "error": error, "is_interrupt": false,
        ]
    }

    private func failureAnswer(_ make: (String) -> [String: Any]) throws -> String {
        let repo = try MCPTestRepo.make(declaring: "Depot")
        try MCPTestRepo.add([DiagnosticNoteTests.producerPath: DiagnosticNoteTests.producer], to: repo)
        let recorded = RecordedOutput()
        PostToolUseCommand.answerFailure(to: make(repo.path), output: recorded.output)
        return recorded.printed
    }

    @Test func aFailedBashCallsErrorIsLocatedUnderTheFailureEvent() throws {
        let printed = try failureAnswer { cwd in
            Self.claude(error: "Exit code 1\n\(cwd)/\(DiagnosticNoteTests.producerPath):6:25: error: x", cwd: cwd)
        }

        #expect(try DiagnosticNoteTests.context(of: printed) == DiagnosticNoteTests.expected)
        let object = try #require(JSONSerialization.jsonObject(with: Data(printed.utf8)) as? [String: Any])
        #expect((object["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String == "PostToolUseFailure")
    }

    @Test func aFailedCallOfAnotherToolIsSilent() throws {
        let printed = try failureAnswer { cwd in
            Self.claude(tool: "Write", error: "Exit code 1\n\(cwd)/\(DiagnosticNoteTests.producerPath):6:25: error: x", cwd: cwd)
        }

        #expect(printed.isEmpty)
    }

    @Test func theEventIsRegisteredForBashAndRoundTripsThroughInstallAndUninstall() throws {
        let event = try #require(SiftClaudeSetup.events.first { $0.name == "PostToolUseFailure" })
        #expect(event.subcommand == "post-tool-use")
        #expect(event.matchers == ["Bash"])

        let applied = try SiftClaudeSetup.hooks.apply(to: nil, command: "/bin/swift-sure post-tool-use", event: event)
        let settings = try #require(JSONSerialization.jsonObject(with: applied.data) as? [String: Any])
        #expect((settings["hooks"] as? [String: Any])?["PostToolUseFailure"] != nil)

        let removal = try SiftClaudeSetup.hooks.remove(from: applied.data, event: event)
        #expect(removal.removed == ["/bin/swift-sure post-tool-use"])
        let after = try #require(JSONSerialization.jsonObject(with: removal.data) as? [String: Any])
        #expect(after["hooks"] == nil)
    }

    @Test func cursorHooksFileWritesThePostToolUseFailureEvent() throws {
        let change = try SiftCursorSetup.hooks.apply(to: nil, binaryWord: "/bin/swift-sure")

        let file = try #require(JSONSerialization.jsonObject(with: change.data) as? [String: Any])

        let entries = try #require((file["hooks"] as? [String: Any])?["postToolUseFailure"] as? [[String: Any]])

        #expect(entries.compactMap { $0["command"] as? String } == ["/bin/swift-sure post-tool-use --agent cursor"])
    }

    @Test func doctorNamesTheFailureEventMissingFromAnOlderHooksFile() throws {
        let home = try TemporaryDirectory.make("failure-doctor-home")
        let directory = home.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = try #require(BuiltExecutable.sift).path
        _ = try SiftCursorSetup.install.install(directory: directory, binary: binary, binaryWord: ShellWord.quoted(binary))
        let file = directory.appendingPathComponent(CursorHooksFile.fileName)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var hooks = try #require(object["hooks"] as? [String: Any])
        hooks["postToolUseFailure"] = nil
        object["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"

        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })

        #expect(throws: ExitCode.self) { try command.run() }

        #expect(recorded.printed.contains("not registered for postToolUseFailure"), "\(recorded.printed)")
    }
}
