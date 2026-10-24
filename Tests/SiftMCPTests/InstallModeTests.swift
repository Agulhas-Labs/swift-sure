//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// `install-hook` registers the whole set by default and run mode with `--run-only`, moves a settings file between the two in either direction, and `uninstall-hook` takes out whichever it finds.
@Suite(.temporaryDirectories)
struct InstallModeTests {
    private static var wrapper: String {
        "/bin/swift-sure"
    }

    /// Runs `install-hook` against `settings` with `arguments`, no allow rules asked, and returns what it printed.
    @discardableResult
    private static func install(_ settings: URL, _ arguments: [String] = [], allowRules: String = "--no-allow-run") throws -> String {
        var command = try InstallHookCommand.parse(["--settings", settings.path, allowRules] + arguments)
        try command.validate()
        command.environment = ["PATH": "/usr/bin:/bin"]
        command.arguments = [wrapper, "install-hook"]
        command.executable = wrapper
        command.settlesLegacy = false
        command.stateDirectory = settings.deletingLastPathComponent().appendingPathComponent(".swift-sure")
        let recorded = RecordedOutput()
        command.output = recorded.output
        try command.run()
        return recorded.printed
    }

    /// Every registered hook as `event|matcher|command`, sorted.
    private static func registered(_ settings: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any], sourceLocation: sourceLocation)
        let hooks = object["hooks"] as? [String: [[String: Any]]] ?? [:]
        return hooks.flatMap { event, entries in
            entries.flatMap { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).map { "\(event)|\(entry["matcher"] as? String ?? "")|\($0["command"] as? String ?? "")" }
            }
        }.sorted()
    }

    private static let runSet = [
        "PostToolUse|Bash|\(wrapper) post-tool-use",
        "PostToolUseFailure|Bash|\(wrapper) post-tool-use",
        "PreToolUse|Bash|\(wrapper) pre-tool-use --run-only",
        "Stop||\(wrapper) stop",
        "SubagentStop||\(wrapper) stop",
    ].sorted()

    private static func settingsFile(_ name: String) throws -> URL {
        try TemporaryDirectory.make(name).appendingPathComponent("settings.json")
    }

    @Test
    func runOnlyRegistersExactlyTheRunSet() throws {
        let settings = try Self.settingsFile("mode-default")
        let printed = try Self.install(settings, ["--run-only"])

        #expect(try Self.registered(settings) == Self.runSet)
        #expect(printed.contains("run mode — index off; re-run without --run-only for the lookup tools"))
        #expect(!printed.contains("SessionStart"))
        #expect(RegisteredHooks(settings: settings).isCurrent)
        #expect(RegisteredHooks(settings: settings).note == "index: off (installed with --run-only)")
    }

    @Test
    func theDefaultInstallRegistersTheFullSet() throws {
        let settings = try Self.settingsFile("mode-index")
        try Self.install(settings)

        let found = try Self.registered(settings)

        #expect(found.contains { $0.hasPrefix("SessionStart|") })
        #expect(found.contains { $0.hasPrefix("SubagentStart|") })
        #expect(found.contains { $0.hasPrefix("PreToolUse|") && $0.hasSuffix("\(Self.wrapper) pre-tool-use") })
        #expect(!found.contains { $0.contains("--run-only") })
        #expect(RegisteredHooks(settings: settings).isCurrent)
        #expect(RegisteredHooks(settings: settings).note == nil)
    }

    @Test
    func aReRunChangesNothingInEitherMode() throws {
        for arguments in [[], ["--run-only"]] {
            let settings = try Self.settingsFile("mode-rerun")
            try Self.install(settings, arguments)
            let first = try Data(contentsOf: settings)
            let printed = try Self.install(settings, arguments)

            #expect(try Data(contentsOf: settings) == first, "arguments \(arguments)")
            #expect(printed.contains("hook: already registered"), "arguments \(arguments)")
        }
    }

    @Test
    func anUpgradeFromTheFullSetToRunModeDropsTheIndexSide() throws {
        let settings = try Self.settingsFile("mode-down")
        try Self.install(settings)
        let printed = try Self.install(settings, ["--run-only"])

        #expect(try Self.registered(settings) == Self.runSet)
        #expect(printed.contains("hook: removed (\(Self.wrapper) session-start) — not registered in run mode"), "\(printed)")
        #expect(!printed.contains("replaced stale registration (\(Self.wrapper) session-start)"), "\(printed)")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        let hooks = object["hooks"] as? [String: Any]
        #expect(hooks?["SessionStart"] == nil)
        #expect(hooks?["SubagentStart"] == nil)
        #expect(RegisteredHooks(settings: settings).isCurrent)
    }

    @Test
    func runModeOverTheFullSetKeepsAForeignHook() throws {
        let settings = try Self.settingsFile("mode-foreign")
        try Self.install(settings)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        var hooks = try #require(object["hooks"] as? [String: Any])
        var sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
        sessionStart.append(["hooks": [["type": "command", "command": "/usr/bin/true"]]])
        hooks["SessionStart"] = sessionStart
        object["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: object).write(to: settings)

        try Self.install(settings, ["--run-only"])

        #expect(try Self.registered(settings) == (Self.runSet + ["SessionStart||/usr/bin/true"]).sorted())
    }

    @Test
    func anUpgradeFromRunModeToTheFullSetRestoresTheIndexSide() throws {
        let settings = try Self.settingsFile("mode-up")
        try Self.install(settings, ["--run-only"])
        try Self.install(settings)

        let fresh = try Self.settingsFile("mode-up-fresh")
        try Self.install(fresh)

        #expect(try Self.registered(settings) == Self.registered(fresh))
        #expect(try !Self.registered(settings).contains { $0.contains("--run-only") })
    }

    @Test
    func uninstallRemovesEitherMode() throws {
        for arguments in [[], ["--run-only"]] {
            let settings = try Self.settingsFile("mode-uninstall")
            try Self.install(settings, arguments)
            try UninstallHookCommand.parse(["--settings", settings.path]).run()

            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
            #expect(object["hooks"] == nil, "arguments \(arguments)")
        }
    }

    @Test
    func onlyAdviceRemovesTheRunModePreToolUseAlone() throws {
        let settings = try Self.settingsFile("mode-only-advice")
        try Self.install(settings, ["--run-only"])
        try UninstallHookCommand.parse(["--settings", settings.path, "--only-advice"]).run()

        #expect(try Self.registered(settings) == Self.runSet.filter { !$0.hasPrefix("PreToolUse") })
    }

    @Test
    func commandAndAllowLookupsAreRefusedWithRunOnly() throws {
        for flags in [["--command", "\(Self.wrapper) session-start"], ["--allow-lookups"]] {
            let settings = try Self.settingsFile("mode-refuse")
            #expect(throws: (any Error).self) { try Self.install(settings, flags + ["--run-only"], allowRules: "--allow-run") }
            #expect(!FileManager.default.fileExists(atPath: settings.path))

            let accepted = try Self.settingsFile("mode-accept")
            try Self.install(accepted, flags, allowRules: "--allow-run")
            #expect(FileManager.default.fileExists(atPath: accepted.path))
        }
    }

    @Test
    func aRunModeFileWithoutItsPreToolUseIsNotCurrent() throws {
        let settings = try Self.settingsFile("mode-partial")
        try Self.install(settings, ["--run-only"])
        try UninstallHookCommand.parse(["--settings", settings.path, "--only-advice"]).run()

        #expect(!RegisteredHooks(settings: settings).isCurrent)
        #expect(RegisteredHooks(settings: settings).note?.contains("build and test rewrite is not registered") == true)
    }

    @Test
    func allowRunAddsBothBlocksByDefaultAndOnlyTheRunBlockWithRunOnly() throws {
        let full = try Self.settingsFile("mode-allow-full")
        try Self.install(full, allowRules: "--allow-run")
        #expect(try LookupAllowRules.missing(from: Data(contentsOf: full)).isEmpty)

        let runOnly = try Self.settingsFile("mode-allow-run-only")
        try Self.install(runOnly, ["--run-only"], allowRules: "--allow-run")
        #expect(try !LookupAllowRules.missing(from: Data(contentsOf: runOnly)).isEmpty)
        #expect(try String(contentsOf: runOnly, encoding: .utf8).contains("run --"))
    }

    @Test
    func theAllowRunHelpIsTrueInBothModes() {
        let hook = InstallHookCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let install = InstallCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for help in [hook, install] {
            #expect(help.contains("with --run-only, the builds alone"), "\(help)")
        }

        let gone = "--" + "index"

        #expect(hook.contains("--run-only"))
        #expect(!hook.contains(gone) && !install.contains(gone))
    }
}
