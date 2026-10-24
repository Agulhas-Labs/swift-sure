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

/// `swift-sure doctor` over a scratch Claude Code install of a `--run-only` install, run mode: hooks, no MCP server.
@Suite(.temporaryDirectories)
struct DoctorClaudeRunModeTests {
    @Test
    func aRunModeInstallReadsHealthyWithTheIndexOffLine() throws {
        let run = try Self.doctor(Self.machine(binary: Self.built(), events: SiftClaudeSetup.runEvents, registration: SiftClaudeSetup.runHooks))
        #expect(run.status == 0, "\(run.printed)")
        let lines = run.printed.split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.hasPrefix("claude index: pass — off (installed with --run-only)") }, "\(run.printed)")
        #expect(lines.contains { $0.hasPrefix("claude hooks: pass — ") }, "\(run.printed)")
        #expect(lines.contains { $0.hasPrefix("claude binary: pass — ") }, "\(run.printed)")
        for event in SiftClaudeSetup.runEvents {
            #expect(lines.count { $0.hasPrefix("claude hook \(event.name): pass — ") } == 1, "\(event.name) in \(run.printed)")
        }
        #expect(!run.printed.contains("claude server"), "\(run.printed)")
        #expect(!run.printed.contains(": fail — "), "\(run.printed)")
    }

    @Test
    func aRunModeInstallWithABrokenBinaryStillFails() throws {
        let run = try Self.doctor(Self.machine(binary: "/no/such/place/swift-sure", events: SiftClaudeSetup.runEvents, registration: SiftClaudeSetup.runHooks))

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude binary: fail — /no/such/place/swift-sure is not there, or is not executable"), "\(run.printed)")
    }

    @Test
    func anIndexModeInstallWithNoServerStillReportsTheServerMissing() throws {
        let run = try Self.doctor(Self.machine(binary: Self.built(), events: SiftClaudeSetup.events, registration: SiftClaudeSetup.hooks))

        #expect(run.status == 1, "\(run.printed)")
        #expect(run.printed.contains("claude server: fail — no MCP server named swift-sure"), "\(run.printed)")
        #expect(!run.printed.contains("claude index"), "\(run.printed)")
    }

    /// This build's `swift-sure`.
    private static func built(sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle", sourceLocation: sourceLocation).path
    }

    /// A scratch home where Claude Code is found and `events` are registered for `binary`, with no MCP server.
    private static func machine(binary: String, events: [HookRegistration.Event], registration: HookRegistration) throws -> AgentDetection.Machine {
        let home = try TemporaryDirectory.make("doctor-run-home")
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        var settings: Data?
        for event in events {
            settings = try registration.apply(to: settings, command: "\(ShellWord.quoted(binary)) \(event.subcommand)", event: event).data
        }
        try settings?.write(to: claude.appendingPathComponent("settings.json"))
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        return AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })
    }

    private static func doctor(_ machine: AgentDetection.Machine) throws -> (printed: String, status: Int32) {
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = machine
        do {
            try command.run()
        } catch let exit as ExitCode {
            return (recorded.printed, exit.rawValue)
        }
        return (recorded.printed, 0)
    }
}
