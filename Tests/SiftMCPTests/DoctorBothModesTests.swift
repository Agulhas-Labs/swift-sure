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

/// `swift-sure doctor` over a hooks file holding both modes' entries: a fault, never a healthy run-mode install.
@Suite(.temporaryDirectories)
struct DoctorBothModesTests {
    private static var failLine: String {
        "index: fail — both modes registered; re-run swift-sure install (with or without --run-only)"
    }

    @Test
    func claudeWithBothModesRegisteredFailsTheIndexLine() throws {
        let run = try Self.doctor(home: Self.claudeHome(both: true), codex: false)

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude \(Self.failLine)"), "\(run.printed)")
        #expect(!run.printed.contains("claude index: pass"), "\(run.printed)")
    }

    @Test
    func cursorWithBothModesRegisteredFailsTheIndexLine() throws {
        let home = try TemporaryDirectory.make("doctor-both-cursor")
        let cursor = home.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let binary = try Self.built()
        try SiftCursorSetup.install(directory: cursor, binary: binary, mode: .run)
        let file = cursor.appendingPathComponent("hooks.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var hooks = try #require(object["hooks"] as? [String: [[String: Any]]])
        let other = home.appendingPathComponent("index-side", isDirectory: true)
        try SiftCursorSetup.install(directory: other, binary: binary, mode: .index)
        let indexObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: other.appendingPathComponent("hooks.json"))) as? [String: Any])
        let indexHooks = try #require(indexObject["hooks"] as? [String: [[String: Any]]])
        hooks["preToolUse", default: []] += try #require(indexHooks["preToolUse"])
        object["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        #expect(try SiftCursorSetup.registersBothModes(Data(contentsOf: file)))

        let run = try Self.doctor(home: home, codex: false)

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("cursor \(Self.failLine)"), "\(run.printed)")
        #expect(!run.printed.contains("cursor index: pass"), "\(run.printed)")
    }

    @Test
    func codexWithBothModesRegisteredFailsTheIndexLine() throws {
        let home = try TemporaryDirectory.make("doctor-both-codex")
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        let directory = AgentPaths.codexDirectory(environment: environment)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let word = try ShellWord.quoted(Self.built())
        let run = try SiftCodexSetup.mergeHooks(into: nil, binaryWord: word, mode: .run).data
        let both = try SiftCodexSetup.hooksFile.apply(to: run, binaryWord: word, replacing: []).data
        #expect(SiftCodexSetup.registersBothModes(both))
        try both.write(to: directory.appendingPathComponent(CodexHooksFile.fileName))

        let printed = try Self.doctor(home: home, codex: true)

        #expect(printed.status == 1, "\(printed.printed)")
        #expect(printed.printed.contains("codex \(Self.failLine)"), "\(printed.printed)")
        #expect(!printed.printed.contains("codex index: pass"), "\(printed.printed)")
    }

    @Test
    func aPureRunModeFilePrintsThePassLine() throws {
        let run = try Self.doctor(home: Self.claudeHome(both: false), codex: false)

        #expect(run.status == 0, "\(run.printed)")
        #expect(run.printed.contains("claude index: pass — off (installed with --run-only)"), "\(run.printed)")
    }

    @Test
    func theClaudeHelperIsFalseForAPureRunFileAndAPureIndexFile() throws {
        let runOnly = try Self.settings(events: SiftClaudeSetup.runEvents, registration: SiftClaudeSetup.runHooks)
        let index = try Self.settings(events: SiftClaudeSetup.events, registration: SiftClaudeSetup.hooks)
        let both = try Self.settings(events: SiftClaudeSetup.events, registration: SiftClaudeSetup.hooks, over: runOnly)

        #expect(SiftClaudeSetup.mode(of: runOnly) == .run)
        #expect(!SiftClaudeSetup.registersBothModes(runOnly))
        #expect(!SiftClaudeSetup.registersBothModes(index))
        #expect(SiftClaudeSetup.registersBothModes(both))
        #expect(!SiftClaudeSetup.registersBothModes(nil))
    }

    @Test
    func statusNotesBothModesAndStillNotesAPureRunFile() throws {
        let runOnly = try Self.settings(events: SiftClaudeSetup.runEvents, registration: SiftClaudeSetup.runHooks)
        let both = try Self.settings(events: SiftClaudeSetup.events, registration: SiftClaudeSetup.hooks, over: runOnly)
        let directory = try TemporaryDirectory.make("status-both-modes")
        let file = directory.appendingPathComponent("settings.json")

        try both.write(to: file)
        #expect(RegisteredHooks(settings: file).note == "index: both modes registered — re-run swift-sure install (with or without --run-only)")

        try runOnly.write(to: file)
        #expect(RegisteredHooks(settings: file).note == "index: off (installed with --run-only)")
    }

    private static func built(sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle", sourceLocation: sourceLocation).path
    }

    private static func settings(events: [HookRegistration.Event], registration: HookRegistration, over base: Data? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        var settings = base
        for event in events {
            settings = try registration.apply(to: settings, command: "\(ShellWord.quoted("/usr/local/bin/swift-sure")) \(event.subcommand)", event: event).data
        }
        return try #require(settings, sourceLocation: sourceLocation)
    }

    /// A scratch home where Claude Code holds the run set, and with `both` the index set's hooks as well.
    private static func claudeHome(both: Bool) throws -> URL {
        let home = try TemporaryDirectory.make("doctor-both-claude")
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let binary = try built()
        var data: Data?
        for event in SiftClaudeSetup.runEvents {
            data = try SiftClaudeSetup.runHooks.apply(to: data, command: "\(ShellWord.quoted(binary)) \(event.subcommand)", event: event).data
        }
        if both {
            for event in SiftClaudeSetup.events {
                data = try SiftClaudeSetup.hooks.apply(to: data, command: "\(ShellWord.quoted(binary)) \(event.subcommand)", event: event).data
            }
        }
        try data?.write(to: claude.appendingPathComponent("settings.json"))
        return home
    }

    private static func doctor(home: URL, codex: Bool) throws -> (printed: String, status: Int32) {
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })
        if codex {
            command.codex = FakeCodex()
        }
        do {
            try command.run()
        } catch let exit as ExitCode {
            return (recorded.printed, exit.rawValue)
        }
        return (recorded.printed, 0)
    }
}
