//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SiftCore

/// `swift-sure install` — finds Claude Code, Cursor and Codex on this machine and installs into each one chosen, through the same installers as `install-hook`, ending with one summary.
///
/// One agent's failure is said and the others still run; the exit status is 1 when any failed. A second run changes nothing and says so.
struct InstallCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "install",
            abstract: "Set \(ProductName.current.binary) up in every agent found on this machine — Claude Code, Cursor, Codex — asking once per agent (idempotent; re-run to upgrade).",
            discussion: """
            Without a terminal to ask on, nothing is installed unless --yes, --all or --agent says what to install into.
            Exits 1 when any agent's install failed; the others are still installed.
            """
        )
    }

    @Option(name: .customLong("agent"), help: "Install into this agent — claude, cursor or codex — whether or not it was found, without asking; repeat for more than one.")
    var agents: [InstallHookCommand.Agent] = []

    @Flag(name: .customLong("all"), help: "Install into all three agents, whether or not each was found, without asking.")
    var all = false

    @Flag(name: .customLong("yes"), help: "Install into every agent found, without asking.")
    var yes = false

    @Flag(name: .customLong("dry-run"), help: "Say what was found and what an install would write; write nothing and run nothing.")
    var dryRun = false

    @Flag(name: .customLong("allow-run"), help: "For Claude Code, add both blocks of allow rules, the lookups and the builds the hook wraps in `\(ProductName.current.binary) run`, without asking.")
    var allowRun = false

    @Flag(name: .customLong("allow-lookups"), help: "For Claude Code, add only the allow rules for `\(ProductName.current.binary) digest`, `where`, `search` and `strings`, without asking.")
    var allowLookups = false

    @Option(name: .customLong("cursor-dir"), help: "With Cursor installed, the directory holding Cursor's mcp.json and hooks.json to install into (defaults to ~/.cursor); it does not pick Cursor.")
    var cursorDirectory: String?

    @Option(name: .customLong("codex-dir"), help: "With Codex installed, the Codex home to install into, holding hooks.json and config.toml (defaults to $CODEX_HOME, else ~/.codex); it does not pick Codex.")
    var codexDirectory: String?

    /// Where the answer goes, injected so a test can read what the install printed.
    var output: CommandOutput = .standard

    /// Everything detection reads and every path is resolved from, injected so a test stands in for the whole machine.
    var machine = AgentDetection.Machine(environment: ProcessInfo.processInfo.environment)

    /// Who is asked whether to install into each agent found and whether to add Claude Code's allow rules, and whether anyone is there to ask, injected so a test answers for the terminal or its absence.
    var prompt: AllowRunPrompt = .standard

    /// Who runs `claude mcp`, injected so a test never runs the real `claude`; `nil` runs the one on the PATH the machine's environment names.
    var claude: (any ClaudeMcpRunner)?

    /// Who runs `codex mcp`, injected so a test never runs the real `codex`; `nil` runs the one on the PATH the machine's environment names.
    var codex: (any CodexMcpRunner)?

    /// The command line this process was started with, injected so a test can say how the binary was invoked.
    var arguments: [String] = CommandLine.arguments

    /// This process's own executable, injected so a test can say which file is running.
    var executable: String? = Bundle.main.executablePath

    /// Who starts each of the other Fieldwork tools' installs, injected so a test never runs a real one; the default gives the child this terminal.
    var familyLaunch: Family.Launch = Family.launchInheritingTerminal

    /// Refuses `--cursor-dir` or `--codex-dir` when the agents named leave that agent out, so the flag is never silently ignored.
    func validate() throws {
        guard cursorDirectory == nil || agents.isEmpty || agents.contains(.cursor) else {
            throw ValidationError("--cursor-dir applies only when Cursor is installed — add --agent cursor")
        }
        guard codexDirectory == nil || agents.isEmpty || agents.contains(.codex) else {
            throw ValidationError("--codex-dir applies only when Codex is installed — add --agent codex")
        }
    }

    func run() throws {
        let environment = machine.environment
        let binary = InstallHookCommand.binaryPath(invokedAs: arguments.first ?? SiftPaths.binaryName, environment: environment, executable: executable)
        if InvokedBinary.isInNpxCache(binary) {
            throw InstallHookCommand.npxCacheRefusal(binary, rerun: "\(ProductName.current.binary) install")
        }
        let detection = AgentDetection.detect(machine, tool: .sift)
        let flags = AgentSelection.Flags(agents: agents.compactMap { Agent(rawValue: $0.rawValue) }, all: all, yes: yes, dryRun: dryRun)
        let directories = AgentDirectories(cursor: cursorDirectory, codex: codexDirectory)
        var selection = AgentSelection.decide(flags, detection: detection, isInteractive: prompt.isInteractive)
        if case let .ask(found) = selection {
            output.emit(directories.text(detection, environment: environment))
            selection = AgentSelection.afterAsking(accepted: InstallPrompt(tool: .sift, ask: prompt.ask).choose(found))
        }
        switch selection {
        case .needsFlags:
            directories.ignoredNotes(picks: []).forEach(output.emit)
            output.emit(AgentSelection.needsFlagsText(detected: detection, tool: .sift))
        case .nothingDetected:
            directories.ignoredNotes(picks: []).forEach(output.emit)
            output.emit(AgentSelection.nothingDetectedText(detection, tool: .sift))
        case let .nothingToDo(reason):
            directories.ignoredNotes(picks: []).forEach(output.emit)
            output.emit(reason)
        case .ask:
            break
        case let .install(picks) where dryRun:
            directories.ignoredNotes(picks: picks).forEach(output.emit)
            for line in InstallDryRun.lines(picks, detection: detection, binary: binary, environment: environment, claudeOnPath: machine.pathLookup("claude") != nil, directories: directories) {
                output.emit(line)
            }
            try runFamily(picks, binary: binary, siftFailed: false)
        case let .install(picks):
            if allowRun || allowLookups, !picks.contains(where: { $0.agent == .claude }) {
                let flags = [allowRun ? "--allow-run" : nil, allowLookups ? "--allow-lookups" : nil].compactMap(\.self)
                output.emit("note: \(flags.joined(separator: " and ")) \(flags.count > 1 ? "apply" : "applies") only to Claude Code's permission rules, and Claude Code is not being installed, so \(flags.count > 1 ? "they were" : "it was") ignored")
            }
            directories.ignoredNotes(picks: picks).forEach(output.emit)
            let failed = install(picks, binary: binary)
            try runFamily(picks, binary: binary, siftFailed: failed)
        }
    }

    /// Runs each pick's step, printing its note, its section and then the summary; returns whether any step failed.
    private func install(_ picks: [AgentSelection.Pick], binary: String) -> Bool {
        var reports: [InstallStepReport] = []
        let summary = InstallSummary.sift
        for pick in picks {
            if let note = pick.note {
                output.emit(note)
            }
            let report = step(pick.agent, binary: binary)
            for line in summary.section(report) {
                output.emit(line)
            }
            reports.append(report)
        }
        let claudeLeft = picks.contains { $0.agent == .claude } && ClaudePluginState(environment: machine.environment).enabledID != nil
        for line in summary.summary(reports) {
            output.emit(claudeLeft && line.hasPrefix("  \(Agent.claude.harness): ") ? "  " + ClaudePluginState.installSummaryVerdict : line)
        }
        return reports.contains { !$0.failures.isEmpty }
    }

    /// Runs the other Fieldwork tools' installs once, into the agents SwiftSure installed into, each announced before it starts; exits 1 when SwiftSure's own steps or any member failed.
    private func runFamily(_ picks: [AgentSelection.Pick], binary: String, siftFailed: Bool) throws {
        let flags = AgentSelection.Flags(agents: picks.map(\.agent), all: false, yes: true, dryRun: dryRun)
        let launch = familyLaunch
        let output = output
        let results = Family.install(
            members: SiftFamily.members,
            caller: .sift,
            flags: flags,
            environment: machine.environment,
            besideDirectory: (binary as NSString).deletingLastPathComponent
        ) { executable, arguments, environment in
            output.emit("family: running \((executable as NSString).lastPathComponent) \(arguments.joined(separator: " "))")
            return try launch(executable, arguments, environment)
        }
        for result in results where !result.succeeded {
            output.emit(result.launchFailure.map { "family: \(result.member) install could not be started: \($0)" } ?? "family: \(result.member) install exited \(result.exitStatus)")
        }
        if siftFailed || results.contains(where: { !$0.succeeded }) {
            throw ExitCode(1)
        }
    }

    /// One agent's step, its lines captured and its failure kept to itself.
    private func step(_ agent: Agent, binary: String) -> InstallStepReport {
        let environment = machine.environment
        let capture = InstallCapture()
        return InstallStepReport.attempt(agent, capture: capture) {
            do {
                switch agent {
                case .claude:
                    return try ClaudeInstallStep(
                        binary: binary,
                        environment: environment,
                        arguments: arguments,
                        executable: executable,
                        runner: claude ?? ClaudeCLI(environment: environment),
                        prompt: prompt,
                        allowRun: allowRun,
                        allowLookups: allowLookups
                    ).run(output: capture.output)
                case .cursor:
                    var report = try SiftCursorSetup.step.run(binary: binary, environment: environment, directory: cursorDirectory)
                    let directory = cursorDirectory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
                    let legacy = try LegacyCursorCleanup.settle(directory: directory, installing: true, installFailed: !report.failures.isEmpty, written: report.written)
                    report.lines += legacy.lines + legacy.notes
                    report.written += legacy.written.filter { !report.written.contains($0) }
                    report.lines.forEach(capture.output.emit)
                    return report
                case .codex:
                    return try CodexInstallStep.run(binary: binary, environment: environment, directory: codexDirectory, runner: codex ?? CodexCLI(environment: environment), output: capture.output)
                }
            } catch let exit as ExitCode {
                throw InstallStepStopped(status: exit.rawValue)
            }
        }
    }
}

extension InstallCommand {
    /// Only the flags come off the command line; the injected parts keep their defaults on the parse path.
    enum CodingKeys: String, CodingKey {
        case agents
        case all
        case yes
        case dryRun
        case allowRun
        case allowLookups
        case cursorDirectory
        case codexDirectory
    }
}
