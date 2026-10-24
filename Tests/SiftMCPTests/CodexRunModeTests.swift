//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `--run-only` for Codex: the shell hooks alone in `hooks.json`, no session start, and no server of ours in `codex mcp`; re-running the install switches modes either way.
@Suite(.temporaryDirectories)
struct CodexRunModeTests {
    private static var foreignHooks: String {
        #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/usr/local/bin/audit-log.sh","type":"command"}],"matcher":"Bash"}]}}"#
    }

    @Test
    func aRunInstallFromEmptyWritesExactlyTheRunSetAndRunsNoAdd() throws {
        let scratch = try TemporaryDirectory.make("codex-run-empty")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex()

        let printed = try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        #expect(try Self.registered(home) == [
            "PreToolUse": ["\(binary.path) pre-tool-use --run-only"],
            "PostToolUse": ["\(binary.path) post-tool-use --run-only"],
        ])
        #expect(try Self.matchers(home) == ["PreToolUse": ["*"], "PostToolUse": ["*"]])
        #expect(!codex.calls.contains { $0.arguments.starts(with: ["mcp", "add"]) })
        #expect(codex.server == nil)
        #expect(printed.contains("run mode — index off; re-run without --run-only for the lookup tools"), "\(printed)")
        #expect(!printed.contains("mcp: registered"), "\(printed)")
    }

    @Test
    func runOverAnIndexInstallLeavesOneHandlerOfOursAndRemovesTheServerThroughTheRunner() throws {
        let scratch = try TemporaryDirectory.make("codex-run-switch")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = try CodexInstallHookTests.codexHome(in: scratch, hooks: Self.foreignHooks)
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--codex-dir", home.path], binary: binary, codex: codex)
        #expect(codex.server != nil)

        let printed = try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        let registered = try Self.registered(home)
        // The foreign group keeps the first position, since Codex keys a hook's trust by where it sits.
        #expect(registered["PreToolUse"] == ["/usr/local/bin/audit-log.sh", "\(binary.path) pre-tool-use --run-only"])
        #expect(registered["PostToolUse"] == ["\(binary.path) post-tool-use --run-only"])
        #expect(registered["SessionStart"] == nil)
        #expect(codex.server == nil)
        #expect(codex.calls.map(\.arguments).contains(["mcp", "remove", "swift-sure"]))
        #expect(printed.contains("mcp: removed swift-sure — \(binary.path) mcp"), "\(printed)")
    }

    @Test
    func aForeignServerOfTheNameIsLeftAlone() throws {
        let scratch = try TemporaryDirectory.make("codex-run-foreign")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex(server: ("/usr/local/bin/other", ["serve"]))

        let printed = try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        #expect(codex.server?.command == "/usr/local/bin/other")
        #expect(!codex.calls.contains { $0.arguments.starts(with: ["mcp", "remove"]) })
        #expect(printed.contains("mcp: left alone — a server named swift-sure runs something else"), "\(printed)")
        #expect(try Self.registered(home)["PreToolUse"] == ["\(binary.path) pre-tool-use --run-only"])
    }

    @Test
    func indexOverARunInstallRestoresWhatAFreshIndexInstallWritesAndReaddsTheServer() throws {
        let scratch = try TemporaryDirectory.make("codex-run-back")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let fresh = try CodexInstallHookTests.codexHome(in: scratch, named: "fresh", hooks: Self.foreignHooks)
        let switched = try CodexInstallHookTests.codexHome(in: scratch, named: "switched", hooks: Self.foreignHooks)
        try CodexInstallHookTests.install(["--codex-dir", fresh.path], binary: binary, codex: FakeCodex())
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--run-only", "--codex-dir", switched.path], binary: binary, codex: codex)
        #expect(codex.server == nil)

        try CodexInstallHookTests.install(["--codex-dir", switched.path], binary: binary, codex: codex)

        #expect(try Data(contentsOf: switched.appendingPathComponent("hooks.json")) == Data(contentsOf: fresh.appendingPathComponent("hooks.json")))
        #expect(codex.server?.command == binary.path)
        #expect(try Self.registered(switched)["SessionStart"] == ["\(binary.path) session-start"])
    }

    @Test
    func aSecondRunInstallChangesNothing() throws {
        let scratch = try TemporaryDirectory.make("codex-run-again")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)
        let first = try Data(contentsOf: home.appendingPathComponent("hooks.json"))

        let again = try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        #expect(try Data(contentsOf: home.appendingPathComponent("hooks.json")) == first)
        #expect(again.contains("hooks: already registered — PreToolUse, PostToolUse"), "\(again)")
    }

    @Test
    func anUninstallAfterARunInstallLeavesNoneOfOurHandlers() throws {
        let scratch = try TemporaryDirectory.make("codex-run-uninstall")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = try CodexInstallHookTests.codexHome(in: scratch, hooks: Self.foreignHooks)
        let foreign = try Data(contentsOf: home.appendingPathComponent("hooks.json"))
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        let removed = try CodexInstallHookTests.uninstall(home, codex: codex)

        #expect(removed.contains("hooks: removed PreToolUse — \(binary.path) pre-tool-use --run-only"), "\(removed)")
        #expect(removed.contains("hooks: removed PostToolUse — \(binary.path) post-tool-use --run-only"), "\(removed)")
        #expect(try Data(contentsOf: home.appendingPathComponent("hooks.json")) == foreign)
    }

    @Test
    func doctorPassesARunInstallWithTheIndexLineAndNoServerCheck() throws {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle").path
        let home = try TemporaryDirectory.make("doctor-codex-run")
        var environment = InstallCommandHarness.environment(home: home)
        environment["PATH"] = "/usr/bin:/bin"
        let directory = AgentPaths.codexDirectory(environment: environment)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CodexHooksFile.install(into: nil, binaryWord: ShellWord.quoted(binary), mode: .run).data.write(to: directory.appendingPathComponent(CodexHooksFile.fileName))
        let recorded = RecordedOutput()
        var command = try DoctorCommand.parse([])
        command.output = recorded.output
        command.machine = AgentDetection.Machine(environment: environment, applications: home, pathLookup: { _ in nil })
        command.codex = FakeCodex()

        try command.run()

        let printed = recorded.printed

        #expect(printed.contains("codex index: pass — off (installed with --run-only)"), "\(printed)")
        #expect(printed.contains("codex hooks: pass — registered for PreToolUse, PostToolUse"), "\(printed)")
        #expect(printed.contains("codex binary: pass"), "\(printed)")
        #expect(printed.contains("codex hook PreToolUse: pass"), "\(printed)")
        #expect(!printed.contains("codex server:"), "\(printed)")
        #expect(!printed.contains("codex mcp server:"), "\(printed)")
    }

    @Test
    func aDryRunNamesTheModeAndWritesNothing() throws {
        let machine = try InstallCommandHarness()

        let run = try machine.run(["--dry-run", "--run-only", "--agent", "codex"])
        let index = try machine.run(["--dry-run", "--agent", "codex"])

        #expect(run.status == 0)
        #expect(run.lines.contains { $0.hasPrefix("Codex mode: run (--run-only)") }, "\(run.printed)")
        #expect(index.lines.contains { $0.hasPrefix("Codex mode: index") }, "\(index.printed)")
        #expect(machine.codex.calls.isEmpty)
        #expect(try machine.files().keys.allSatisfy { !$0.hasSuffix("hooks.json") })
    }

    @Test
    func theInstallStepPassesRunModeThroughToCodex() throws {
        let machine = try InstallCommandHarness()

        let run = try machine.run(["--yes", "--run-only", "--agent", "codex"])

        #expect(run.status == 0, "\(run.printed)")
        #expect(!machine.codex.calls.contains { $0.arguments.starts(with: ["mcp", "add"]) })
        let hooks = try Data(contentsOf: machine.home.appendingPathComponent(".codex/hooks.json"))
        #expect(CodexHooksFile.mode(of: hooks) == .run)
    }

    @Test
    func aForeignGroupAfterOursKeepsItsIndexThroughIndexRunIndex() throws {
        let scratch = try TemporaryDirectory.make("codex-run-order")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--codex-dir", home.path], binary: binary, codex: codex)
        try Self.appendForeignGroups(home, events: ["PreToolUse", "PostToolUse", "SessionStart"])
        let before = try Self.events(home, sourceLocation: #_sourceLocation)

        try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)
        let run = try Self.events(home, sourceLocation: #_sourceLocation)
        try CodexInstallHookTests.install(["--codex-dir", home.path], binary: binary, codex: codex)
        let back = try Self.events(home, sourceLocation: #_sourceLocation)

        for event in ["PreToolUse", "PostToolUse"] {
            #expect(Self.commands(run[event]) == [["\(binary.path) \(event == "PreToolUse" ? "pre-tool-use" : "post-tool-use") --run-only"], ["/usr/local/bin/foreign-\(event).sh"]], "\(event): \(Self.commands(run[event]))")
            #expect(Self.commands(back[event]) == Self.commands(before[event]), "\(event): \(Self.commands(back[event]))")
        }
        // The session start group is ours alone, so run mode drops it and the foreign group after it moves up.
        #expect(Self.commands(run["SessionStart"]) == [["/usr/local/bin/foreign-SessionStart.sh"]])
    }

    @Test
    func aForeignHandlerSharingOurGroupKeepsItsSlot() throws {
        let scratch = try TemporaryDirectory.make("codex-run-shared-group")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--codex-dir", home.path], binary: binary, codex: codex)
        var file = try CursorInstallHookTests.object(at: home.appendingPathComponent("hooks.json"))
        var events = try #require(file["hooks"] as? [String: Any])
        var groups = try #require(events["PreToolUse"] as? [[String: Any]])
        var handlers = try #require(groups[0]["hooks"] as? [[String: Any]])
        handlers.insert(["type": "command", "command": "/usr/local/bin/before.sh"], at: 0)
        handlers.append(["type": "command", "command": "/usr/local/bin/after.sh"])
        groups[0]["hooks"] = handlers
        events["PreToolUse"] = groups
        file["hooks"] = events
        try CursorConfigJSON.encode(file).write(to: home.appendingPathComponent("hooks.json"))

        try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        #expect(try Self.commands(Self.events(home, sourceLocation: #_sourceLocation)["PreToolUse"]) == [["/usr/local/bin/before.sh", "\(binary.path) pre-tool-use --run-only", "/usr/local/bin/after.sh"]])
    }

    @Test
    func droppingOurSessionStartGroupAheadOfAForeignOneSaysTheForeignOneMoved() throws {
        let scratch = try TemporaryDirectory.make("codex-run-moved-line")
        let binary = try CursorInstallHookTests.binary(in: scratch)
        let home = scratch.appendingPathComponent("codex-home")
        let codex = FakeCodex()
        try CodexInstallHookTests.install(["--codex-dir", home.path], binary: binary, codex: codex)
        try Self.appendForeignGroups(home, events: ["SessionStart"])

        let printed = try CodexInstallHookTests.install(["--run-only", "--codex-dir", home.path], binary: binary, codex: codex)

        #expect(printed.contains("hooks: SessionStart groups after ours moved up; Codex will ask to trust them again"), "\(printed)")
        #expect(!printed.contains("hooks: PreToolUse groups after ours moved up"), "\(printed)")
    }

    @Test
    func aRunDryRunNeverMentionsRegisteringTheServer() throws {
        let machine = try InstallCommandHarness()

        let run = try machine.run(["--dry-run", "--run-only", "--agent", "codex"])

        #expect(run.status == 0)
        #expect(!run.printed.contains("codex mcp add"), "\(run.printed)")
        #expect(run.lines.contains { $0.contains("config.toml") && $0.contains("codex mcp remove") }, "\(run.printed)")
    }

    /// Adds a foreign group after the last group of each of `events` in `home`'s `hooks.json`.
    private static func appendForeignGroups(_ home: URL, events names: [String], sourceLocation: SourceLocation = #_sourceLocation) throws {
        var file = try CursorInstallHookTests.object(at: home.appendingPathComponent("hooks.json"))
        var events = try #require(file["hooks"] as? [String: Any], sourceLocation: sourceLocation)
        for name in names {
            var groups = try #require(events[name] as? [Any], sourceLocation: sourceLocation)
            groups.append(["hooks": [["type": "command", "command": "/usr/local/bin/foreign-\(name).sh"]]])
            events[name] = groups
        }
        file["hooks"] = events
        try CursorConfigJSON.encode(file).write(to: home.appendingPathComponent("hooks.json"))
    }

    /// The commands of each group, in order.
    private static func commands(_ groups: [[String: Any]]?) -> [[String]] {
        (groups ?? []).map { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    /// Every command of any hook in `home`'s `hooks.json`, by event, in file order.
    private static func registered(_ home: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: [String]] {
        try events(home, sourceLocation: sourceLocation).mapValues { groups in
            groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
    }

    /// The matcher of each group of each event in `home`'s `hooks.json`.
    private static func matchers(_ home: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: [String]] {
        try events(home, sourceLocation: sourceLocation).mapValues { groups in groups.compactMap { $0["matcher"] as? String } }
    }

    private static func events(_ home: URL, sourceLocation: SourceLocation) throws -> [String: [[String: Any]]] {
        let file = try CursorInstallHookTests.object(at: home.appendingPathComponent("hooks.json"), sourceLocation: sourceLocation)
        return try #require(file["hooks"] as? [String: [[String: Any]]], sourceLocation: sourceLocation)
    }
}
