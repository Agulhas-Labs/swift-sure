//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// What `swift-sure install --dry-run` prints: what was found and what an install would do to each file it writes, with what the Claude Code server and rule steps would do, read without writing a file or running a command.
struct InstallDryRun {
    /// The answer for `picks`, found in `detection`, for `binary` under the home `environment` names.
    ///
    /// `directories` moves Cursor's or Codex's files to where `--cursor-dir` or `--codex-dir` sends the install.
    static func lines(_ picks: [AgentSelection.Pick], detection: AgentDetection, binary: String, environment: [String: String], claudeOnPath: Bool = true, directories: AgentDirectories = AgentDirectories()) -> [String] {
        var lines = [text(detection, binary: binary, environment: environment, claudeOnPath: claudeOnPath, directories: directories)]
        lines += picks.compactMap(\.note)
        if picks.contains(where: { $0.agent == .claude }) {
            let config = AgentPaths.claudeConfig(environment: environment)
            let rule = AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: environment)
            let serverPlan = SiftClaudeSetup.mcp.plan(config: config, binary: binary)
            let rulePlan = SiftClaudeSetup.rule.plan(source: SiftClaudeSetup.rule.source(forBinary: binary), destination: rule)
            lines.append("Claude Code MCP server: \(describe(serverPlan, binary: binary, config: config, claudeOnPath: claudeOnPath))")
            lines += LegacyBandCleanup.pending(settings: AgentPaths.claudeSettings(environment: environment), claudeOnPath: claudeOnPath)
            lines.append("Claude Code rule: \(describe(rulePlan, at: rule))")
            lines += LegacyRegistrationCleanup.pending(
                SiftUninstall.Locations.standard(environment: environment, usageLog: UsageLog.standardFileURL(environment: environment)),
                names: ProductName.recognised,
                serverRegistered: registers(serverPlan, claudeOnPath: claudeOnPath),
                ruleInstalled: installs(rulePlan, at: rule),
                claudeOnPath: claudeOnPath
            )
        }
        let names = picks.map(\.agent.harness).joined(separator: ", ")
        lines.append("dry run: nothing written and nothing run; without --dry-run this installs into \(names)")
        return lines
    }

    /// One line per agent as detection says it, with each file an install writes beneath it and what the install would do to that file as it stands.
    ///
    /// A file the install would change reads exactly as ``AgentDetection/text`` has it, so on a machine with nothing installed the two are the same text.
    private static func text(_ detection: AgentDetection, binary: String, environment: [String: String], claudeOnPath: Bool, directories: AgentDirectories) -> String {
        detection.findings.flatMap { finding in
            let states = states(of: finding.agent, binary: binary, environment: environment, claudeOnPath: claudeOnPath, directories: directories)
            return [finding.line] + finding.targets.map { target in
                let moved = directories.moved(target, of: finding.agent, environment: environment)
                return (states[moved.path] ?? .write).line(path: moved.path, what: moved.what)
            }
        }
        .joined(separator: "\n")
    }

    /// What an install into `agent` would do to each file it writes, by path, read through the installers' own merges.
    private static func states(of agent: Agent, binary: String, environment: [String: String], claudeOnPath: Bool, directories: AgentDirectories) -> [String: TargetState] {
        let word = ShellWord.quoted(binary)
        switch agent {
        case .claude:
            let settings = AgentPaths.claudeSettings(environment: environment)
            let config = AgentPaths.claudeConfig(environment: environment)
            let rule = AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: environment)
            return [
                settings.path: TargetState.reading { try claudeSettings(settings, word: word) },
                config.path: server(SiftClaudeSetup.mcp.plan(config: config, binary: binary), binary: binary, claudeOnPath: claudeOnPath),
                rule.path: self.rule(SiftClaudeSetup.rule.plan(source: SiftClaudeSetup.rule.source(forBinary: binary), destination: rule), at: rule),
            ]
        case .cursor:
            let directory = directories.cursor.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
            let mcp = directory.appendingPathComponent(CursorMcpFile.fileName)
            let hooks = directory.appendingPathComponent(CursorHooksFile.fileName)
            return [
                mcp.path: TargetState.reading {
                    switch try SiftCursorSetup.mcp.apply(to: SiftCursorSetup.read(mcp), binary: binary).outcome {
                    case .registered, .replaced:
                        .write
                    case .unchanged, .removed:
                        .installed
                    case let .foreign(existing):
                        TargetState(verb: "left alone", reason: "a server named \(SiftCursorSetup.mcp.server.name) runs something else (\(existing))")
                    }
                },
                hooks.path: TargetState.reading {
                    try SiftCursorSetup.hooks.apply(to: SiftCursorSetup.read(hooks), binaryWord: word).changed ? .write : .installed
                },
            ]
        case .codex:
            let home = CodexInstall.home(flag: directories.codex, environment: environment)
            let hooks = home.directory.appendingPathComponent(CodexHooksFile.fileName)
            let config = home.directory.appendingPathComponent("config.toml")
            return [
                hooks.path: TargetState.reading {
                    try CodexHooksFile.apply(to: SettingsFile.read(hooks, agent: "codex", flag: "--codex-dir"), binaryWord: word).changed ? .write : .installed
                },
                // Only `codex mcp get` can say what the file registers, and a dry run runs nothing; a file that is not there registers nothing.
                config.path: PathKind.of(config) == .absent
                    ? .write
                    : TargetState(verb: "not checked", reason: "only `codex mcp get` can say whether \(ProductName.current.binary) is registered there"),
            ]
        }
    }

    /// The Claude Code settings as the install merges them: every hook, and an older install's status line taken out; `swift-sure install` never adds the allow rules, having no terminal to ask on.
    private static func claudeSettings(_ url: URL, word: String) throws -> TargetState {
        var merged = try SettingsFile.read(url, agent: "claude", flag: "--settings")
        var changed = false
        for event in SiftClaudeSetup.events {
            let result = try SiftClaudeSetup.hooks.apply(to: merged, command: "\(word) \(event.subcommand)", event: event)
            guard result.changed else { continue }
            merged = result.data
            changed = true
        }
        // Only SwiftSure's own status line is named: the install takes it out, and leaves someone else's unmentioned.
        if case .removed = try StatuslineRegistration.remove(from: merged) {
            return TargetState(verb: "would write", reason: "the status line an older install registered would be removed")
        }
        return changed ? .write : .installed
    }

    private static func server(_ plan: ClaudeMcpInstall.Plan, binary: String, claudeOnPath: Bool) -> TargetState {
        switch plan {
        case .absent:
            claudeOnPath ? .write : TargetState(verb: "would not write", reason: "`claude` is not on PATH — register the server with: \(SiftClaudeSetup.server.manual(binary: binary))")
        case let .stale(previous):
            claudeOnPath ? .write : TargetState(verb: "would not write", reason: "`claude` is not on PATH — replace the stale registration (\(previous)) with: \(SiftClaudeSetup.server.removalCommand); \(SiftClaudeSetup.server.manual(binary: binary))")
        case .current:
            .installed
        case let .foreign(existing):
            TargetState(verb: "left alone", reason: "a server named \(ProductName.current.mcpServer) runs something else (\(existing))")
        case let .unreadable(reason):
            TargetState(verb: "would be refused", reason: reason)
        }
    }

    private static func rule(_ plan: ClaudeRuleInstall.Plan, at destination: URL) -> TargetState {
        switch plan {
        case .copy, .replace:
            .write
        case .identical:
            .installed
        case .noSource:
            noSourceState(at: destination)
        case let .symlink(target):
            TargetState(verb: "left alone", reason: "a symlink to \(target)")
        case .refused:
            TargetState(verb: "left alone", reason: "not a plain file")
        }
    }

    /// Whether a server the cleanup counts as the current name's would be registered once an install had run `plan`: a stale one is, replaced or left, since it still runs this tool.
    private static func registers(_ plan: ClaudeMcpInstall.Plan, claudeOnPath: Bool) -> Bool {
        switch plan {
        case .current, .stale:
            true
        case .absent:
            claudeOnPath
        case .foreign, .unreadable:
            false
        }
    }

    /// Whether a rule would be at `destination` once an install had run `plan`, by the test the cleanup itself makes.
    private static func installs(_ plan: ClaudeRuleInstall.Plan, at destination: URL) -> Bool {
        switch plan {
        case .copy, .replace, .identical:
            true
        case .noSource, .symlink, .refused:
            FileManager.default.fileExists(atPath: destination.path)
        }
    }

    private static func describe(_ plan: ClaudeMcpInstall.Plan, binary: String, config: URL, claudeOnPath: Bool) -> String {
        let manual = SiftClaudeSetup.server.manual(binary: binary)
        return switch plan {
        case .absent where !claudeOnPath:
            "`claude` is not on PATH — register the server with: \(manual)"
        case let .stale(previous) where !claudeOnPath:
            "`claude` is not on PATH — replace the stale registration (\(previous)) with: \(SiftClaudeSetup.server.removalCommand); \(manual)"
        case .absent:
            "would register \(binary) mcp through `claude mcp add`"
        case .current:
            "already registered"
        case let .stale(previous):
            "would replace the stale registration (\(previous)) with \(binary) mcp"
        case let .foreign(existing):
            "would be left alone — a server named \(ProductName.current.mcpServer) runs something else (\(existing))"
        case let .unreadable(reason):
            "would be refused — \(config.path) \(reason)"
        }
    }

    /// What a rule with no `SwiftSure.md` to install from is left as: kept where an earlier install put it, else skipped.
    private static func noSourceState(at rule: URL) -> TargetState {
        let exists = PathKind.of(rule) != .absent
        return TargetState(verb: exists ? "left as installed" : "would be skipped", reason: SiftClaudeSetup.rule.noSourceReason(exists: exists))
    }

    private static func describe(_ plan: ClaudeRuleInstall.Plan, at rule: URL) -> String {
        switch plan {
        case .noSource:
            {
                let state = noSourceState(at: rule)
                return "\(state.verb) — \(state.reason ?? "")"
            }()
        case .copy:
            "would copy \(ProductName.current.displayName).md to \(rule.path)"
        case .identical:
            "already installed"
        case let .symlink(target):
            "would be left as is — \(rule.path) is a symlink to \(target)"
        case .replace:
            "would replace \(rule.path), keeping the previous one beside it"
        case .refused:
            "would not be written — \(rule.path) is not a plain file"
        }
    }
}

extension InstallDryRun {
    /// What an install would do to one file, and why when that is anything but writing it.
    private struct TargetState {
        static let write = TargetState(verb: "would write", reason: nil)
        static let installed = TargetState(verb: "already installed", reason: nil)

        let verb: String
        let reason: String?

        /// The state `read` finds, or the refusal the install would stop on: a file that cannot be read or merged is said, never thrown.
        static func reading(_ read: () throws -> TargetState) -> TargetState {
            do {
                return try read()
            } catch let refused as SettingsFile.Refused {
                return TargetState(verb: "would be refused", reason: refused.reason)
            } catch {
                return TargetState(verb: "would be refused", reason: String(describing: error))
            }
        }

        /// The line beneath the agent's, `would write` reading exactly as detection has it.
        func line(path: String, what: String) -> String {
            "    \(verb) \(path) (\(what))" + (reason.map { " — \($0)" } ?? "")
        }
    }
}
