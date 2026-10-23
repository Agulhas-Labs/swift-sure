//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// `swift-sure install-hook` — registers `session-start` for `SessionStart` and `SubagentStart`, `pre-tool-use` for `PreToolUse`, `post-tool-use` for `PostToolUse` and `stop` for `Stop` and `SubagentStop`, in `~/.claude/settings.json`, and takes out the status line and band an older install left.
///
/// Called by the distribution installer, and safe to run by hand: re-running is the upgrade path, and a registration already pointing at a moved binary is repointed rather than duplicated.
struct InstallHookCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "install-hook",
            abstract: "Register the SessionStart/SubagentStart primer, the PreToolUse advice hook, the PostToolUse reuse nudge, and the Stop/SubagentStop build check with Claude Code, removing an older install's status line and band (idempotent; re-run to upgrade)."
        )
    }

    @Option(name: .customLong("settings"), help: "Settings file to edit (defaults to ~/.claude/settings.json).")
    var settings: String?

    @Option(name: .customLong("command"), help: "Hook command to register (defaults to this binary's own path).")
    var command: String?

    @Flag(
        inversion: .prefixedNo,
        help: "Add (or don't add) both blocks of allow rules, the lookups and the builds the hook wraps in `\(ProductName.current.binary) run`, without asking."
    )
    var allowRun: Bool?

    @Flag(name: .customLong("allow-lookups"), help: "Add only the allow rules for `\(ProductName.current.binary) digest`, `where`, `search` and `strings`, without asking about either block.")
    var allowLookups = false

    @Option(name: .customLong("agent"), help: "The agent to register with: claude (default), cursor or codex. Cursor and Codex support is experimental.")
    var agent: Agent = .claude

    @Option(name: .customLong("cursor-dir"), help: "With --agent cursor, the directory holding Cursor's mcp.json and hooks.json (defaults to ~/.cursor).")
    var cursorDirectory: String?

    @Option(name: .customLong("codex-dir"), help: "With --agent codex, the Codex home holding hooks.json and config.toml (defaults to $CODEX_HOME, else ~/.codex).")
    var codexDirectory: String?

    /// Where the answer goes, injected so a test can read what the install printed.
    var output: CommandOutput = .standard

    /// Who runs `codex mcp`, injected so a test never runs the real `codex`; `nil` runs the one on the PATH ``environment`` names.
    var codex: (any CodexMcpRunner)?

    /// Who runs `claude plugin` for the legacy band's removal, injected so a test never runs the real `claude` against the real settings.
    var runPlugin: @Sendable ([String: String], [String]) -> SiftUninstall.PluginRun = UninstallCommand.claudeRunsPlugin

    /// Who takes out an MCP server an earlier release registered under its own name, injected so a test never runs the real `claude` against the real config.
    var removeLegacyServer: @Sendable ([String: String], ProductName, SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval = { UninstallCommand.claudeRemovesServer(environment: $0, scope: $2, named: $1) }

    /// Whether ``install()`` takes out the earlier name's server and rule itself; `false` leaves that to ``settleLegacyRegistrations()``, for a caller that registers the current ones first.
    var settlesLegacy = true

    /// Who is asked about the allow rules, injected so a test can answer for the terminal or stand in for its absence.
    var prompt: AllowRunPrompt = .standard

    /// The state directory the lookups decline is recorded in, injected so a test never writes the user's; `nil` is `~/.swift-sure` (or `SWIFT_SURE_HOME`) under ``environment``.
    var stateDirectory: URL?

    /// The command line this process was started with, injected so a test can say how the binary was invoked.
    var arguments: [String] = CommandLine.arguments

    /// The environment the binary is looked up in, injected so a test runs the install with its own PATH and home.
    var environment: [String: String] = ProcessInfo.processInfo.environment

    /// This process's own executable, injected so a test can say which file is running.
    var executable: String? = Bundle.main.executablePath

    /// The directory a relative PATH entry is taken against, injected so a test need not change the process's own.
    var currentDirectory = FileManager.default.currentDirectoryPath

    /// Every name this install answers to, the current one first: hooks registered under the others are replaced by the current name's, injected so a test can stand in a rename.
    var names = ProductName.recognised

    /// Refuses a `--command` that `uninstall-hook` would not be able to find again.
    ///
    /// Recognition is by shape — the binary's name plus the subcommand — and it is the *only* handle either the re-run path or the uninstall has on a previous registration. A command outside that shape installs a hook nothing can subsequently see: the uninstall reports a clean sweep while leaving it running, and the next install appends a second primer beside it rather than repointing the first. Validation runs before a byte is written, so the refusal costs nothing.
    func validate() throws {
        try Agent.validate(agent, cursorDirectory: cursorDirectory, codexDirectory: codexDirectory, claudeOnly: [
            settings.map { _ in "--settings" },
            command.map { _ in "--command" },
            allowRun.map { $0 ? "--allow-run" : "--no-allow-run" },
            allowLookups ? "--allow-lookups" : nil,
        ])
        if allowRun == false, allowLookups {
            throw ValidationError("--allow-lookups adds the lookup rules and --no-allow-run adds none; give one of them")
        }
        guard let command, !SiftClaudeSetup.hooks.isOurs(command, subcommand: SiftClaudeSetup.sessionStartSubcommand) else { return }
        throw ValidationError(
            "--command must name this binary and the subcommand it runs, e.g. \"\(executableWord()) \(SiftClaudeSetup.sessionStartSubcommand)\" — "
                + "a command outside that shape is one `uninstall-hook` cannot find again."
        )
    }

    func run() throws {
        try install()
    }

    /// Takes out the server and the rule an earlier release registered under its own name, so they do not sit beside the current name's, once the current ones are in place.
    ///
    /// Skipped for a named settings file, like the band: `claude` edits the user's own config.
    func settleLegacyRegistrations() -> (lines: [String], removed: Bool) {
        guard settings == nil else { return (lines: [], removed: false) }
        return LegacyRegistrationCleanup.settle(SiftUninstall.Locations.standard(environment: environment, usageLog: UsageLog.standardFileURL(environment: environment)), names: names) { [environment, removeLegacyServer] in
            removeLegacyServer(environment, $0, $1)
        }
    }

    /// Runs the install and returns whether it changed anything: `false` is the answer that says every registration was already in place.
    @discardableResult
    func install() throws -> Bool {
        let binary = Self.binaryPath(invokedAs: arguments.first ?? SiftPaths.binaryName, environment: environment, executable: executable, names: names)
        if InvokedBinary.isInNpxCache(binary) {
            throw Self.npxCacheRefusal(binary, rerun: "\(ProductName.current.binary) install-hook")
        }
        if agent == .cursor {
            let directory = cursorDirectory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
            let result = try SiftCursorSetup.installer.install(directory: directory, binary: binary)
            let legacy = try LegacyCursorCleanup.settle(directory: directory, installing: true, installFailed: !result.outcome.failures.isEmpty, written: result.outcome.written)
            let restart = !result.outcome.changed && legacy.changed ? [CursorHookInstaller.restart] : []
            (result.printed + legacy.lines + legacy.written.map { "      \($0)" } + legacy.notes + restart).forEach(output.emit)
            return result.outcome.changed || legacy.changed
        }
        if agent == .codex {
            let home = CodexInstall.home(flag: codexDirectory, environment: environment)
            return try CodexHookInstaller.install(home: home, binary: binary, runner: codex ?? CodexCLI(environment: environment), output: output).changed
        }
        let settingsURL = settings.map { URL(fileURLWithPath: $0) } ?? AgentPaths.claudeSettings(environment: environment)
        // `--command` overrides the primer's command only. The `PreToolUse` hook runs a different
        // subcommand, so it is always built from the binary's own path — an override that pointed both at
        // one command would register a primer where a permission decision is expected.
        let hookCommand = command ?? "\(executableWord()) \(SiftClaudeSetup.sessionStartSubcommand)"

        // Before the read, never between it and the rewrite: `claude plugin` edits this same file, and the rewrite
        // below would put back what it took out. Skipped for a named file, as the uninstall skips it: `claude`
        // edits the user's own settings, so it would read one file and change another.
        let band = settings == nil
            ? LegacyBandCleanup.settle(settings: settingsURL) { runPlugin(environment, $0) }
            : (lines: [], removed: false)

        // A file that is there and cannot be read is refused: read as absent, the merge would replace it with SwiftSure's hooks alone.
        let original = try SettingsFile.read(settingsURL, agent: "claude", flag: "--settings")

        // Run after the read, so an unreadable settings file refuses the install before anything is removed.
        let legacy = settlesLegacy ? settleLegacyRegistrations() : (lines: [], removed: false)

        var merged = original
        var hookChanged = false
        var replaced: [String] = []
        // A hook an earlier release registered under its own binary name comes out first, so the one registered below does not sit beside it.
        for registration in SiftClaudeSetup.hooks(recognising: Array(names.dropFirst())) {
            for event in registration.eventsToRemove() {
                let removal = try registration.remove(from: merged, event: event)
                guard !removal.removed.isEmpty else { continue }
                merged = removal.data
                hookChanged = true
                for previous in removal.removed where !replaced.contains(previous) {
                    replaced.append(previous)
                }
            }
        }
        for event in SiftClaudeSetup.events {
            let eventCommand = event.subcommand == SiftClaudeSetup.sessionStartSubcommand ? hookCommand : "\(executableWord()) \(event.subcommand)"
            let result = try SiftClaudeSetup.hooks(named: names[0]).apply(to: merged, command: eventCommand, event: event)
            guard result.changed else { continue }
            merged = result.data
            hookChanged = true
            // Distinct across events as well as within one: a single moved binary is one fact to report,
            // not one per event it was registered for.
            for previous in result.replaced where !replaced.contains(previous) {
                replaced.append(previous)
            }
        }
        var current = merged ?? Data()

        let (rulesAdded, permissionNote) = try allowRunRules(in: &current)

        var statuslineNote: String?
        // SwiftSure draws no status line any more: one an older install registered comes out, and someone else's is not
        // looked at, so it is not mentioned either.
        if case let .removed(updated, _) = try StatuslineRegistration.remove(from: current) {
            current = updated
            statuslineNote = "statusline: removed (\(ProductName.current.binary) no longer draws one; run \(ProductName.current.binary) report)"
        }

        guard hookChanged || rulesAdded || statuslineNote != nil else {
            output.emit("hook: already registered (\(hookCommand))")
            if let permissionNote {
                output.emit(permissionNote)
            }
            for line in band.lines + legacy.lines {
                output.emit(line)
            }
            return band.removed || legacy.removed
        }

        // Back the file up before every rewrite that changes it, overwriting the previous copy, so the
        // backup holds the state before the latest rewrite rather than the original. It is the user's whole
        // Claude Code configuration and this tool did not author it; the copy is cheap insurance against a
        // merge bug on a machine where nobody is watching.
        let backupNote = try SettingsFile.rewrite(settingsURL, with: current, original: original, tool: .sift)

        for previous in replaced {
            output.emit("hook: replaced stale registration (\(previous))")
        }
        if hookChanged {
            output.emit("hook: registered for SessionStart (\(SiftClaudeSetup.sessionStartMatchers.joined(separator: ", "))) and SubagentStart — \(hookCommand)")
            let preToolUse = SiftClaudeSetup.events.first { $0.subcommand == SiftClaudeSetup.preToolUseSubcommand }
            output.emit("      registered for PreToolUse (\(preToolUse?.matchers.joined(separator: ", ") ?? "")) — \(executableWord()) \(SiftClaudeSetup.preToolUseSubcommand)")
            let postToolUse = SiftClaudeSetup.events.first { $0.subcommand == "post-tool-use" }
            output.emit("      registered for PostToolUse (\(postToolUse?.matchers.joined(separator: ", ") ?? "")) — \(executableWord()) post-tool-use")
            output.emit("      registered for PostToolUseFailure (Bash) — \(executableWord()) post-tool-use")
            output.emit("      registered for Stop and SubagentStop — \(executableWord()) stop")
        } else {
            output.emit("hook: already registered (\(hookCommand))")
        }
        if let statuslineNote {
            output.emit(statuslineNote)
        }
        if let permissionNote {
            output.emit(permissionNote)
        }
        output.emit("      \(SettingsFile.named(settingsURL))")
        if let backupNote {
            output.emit(backupNote)
        }
        for line in band.lines + legacy.lines {
            output.emit(line)
        }
        Self.emitAgentAllowlistNote(to: output)
        return true
    }

    /// Adds the lookup and `swift-sure run` allow rules to `settings` where they are missing and the answer is yes, returning whether any were added and the line saying what happened.
    ///
    /// The answers are `--allow-run` (both blocks), `--no-allow-run` (neither), `--allow-lookups` (the lookups alone), or on a terminal one question per missing block, the lookups first and defaulting to yes (to no once it was declined, which `~/.swift-sure` remembers until a yes or `--allow-lookups`), then the runs, defaulting to no. Never asked without a terminal, and not said when the file already holds what would be asked: where nobody can answer, nothing is added, and the line names the flags that add them.
    private func allowRunRules(in settings: inout Data) throws -> (added: Bool, note: String?) {
        // The shape of `permissions` is looked at only where rules could be added: a refusal
        // (`--no-allow-run`, or no terminal to ask on) leaves it alone, so it never blocks the hooks.
        if allowRun == false {
            return (false, "permissions: nothing added")
        }
        // A flag that gives the lookups answer ends an earlier decline, whether or not the block is already in the file.
        if allowLookups || allowRun == true {
            LookupsDeclineRecord(directory: stateDirectory, environment: environment).clear()
        }
        let asks = allowRun == nil && !allowLookups
        let lookupsMissing = try !LookupAllowRules.missing(from: settings).isEmpty
        let runsMissing = try !RunAllowRules.missing(from: settings).isEmpty
        // `--allow-run` adds the run rules even beside `--allow-lookups`, so a file already holding the lookups is not the end of it.
        let wantsRuns = runsMissing && (allowRun == true || !allowLookups)
        guard lookupsMissing || wantsRuns else {
            return (false, allowLookups ? "permissions: lookups already allowed" : "permissions: wrapped builds and lookups already allowed")
        }
        if asks, !prompt.isInteractive {
            let binary = Self.binaryPath(invokedAs: arguments.first ?? SiftPaths.binaryName, environment: environment, executable: executable, names: names)
            return (false, Self.noTerminalNote(binary: binary, environment: environment, currentDirectory: currentDirectory))
        }
        // A block already in the file is not asked about again.
        let addLookups = lookupsMissing && wantsLookups(asking: asks)
        let addRuns = wantsRuns && (allowRun == true || (asks && AllowRunPrompt.accepts(prompt.ask(AllowRunPrompt.runsQuestion), defaultsTo: false)))
        // Each set is a block of its own, so an install over a file holding only one set adds only the other.
        var added: [String] = []
        if addRuns, let updated = try RunAllowRules.adding(to: settings) {
            settings = updated
            added += RunAllowRules.rules
        }
        if addLookups, let updated = try LookupAllowRules.adding(to: settings) {
            settings = updated
            added += LookupAllowRules.rules
        }
        return added.isEmpty ? (false, "permissions: nothing added") : (true, "permissions: allowed \(added.joined(separator: ", "))")
    }

    /// The permissions line where nobody can answer: the command that adds the rules, the form to type it in from a Claude Code session, and the flag for the lookups alone.
    ///
    /// The command is spelled as the user must type it: bare `swift-sure` where the first `swift-sure` on the PATH in `environment` is this binary, otherwise the binary's own path.
    static func noTerminalNote(binary: String, environment: [String: String], currentDirectory: String) -> String {
        let typed = typedCommand(binary: binary, environment: environment, currentDirectory: currentDirectory)
        return "permissions: nothing added (no terminal to ask in) — to allow \(ProductName.current.binary)'s lookups and wrapped builds without a prompt, run: \(typed) install-hook --allow-run (from Claude Code: ! \(typed) install-hook --allow-run); `\(typed) install-hook --allow-lookups` for the lookups alone"
    }

    /// What the user types to run `binary`: its bare name where the first `swift-sure` on the PATH is this binary, else its quoted path.
    ///
    /// A directory on the PATH after another `swift-sure` does not make the bare name run this one, so the files are compared by resolved path.
    private static func typedCommand(binary: String, environment: [String: String], currentDirectory: String) -> String {
        guard let first = InvokedBinary.onPath(SiftPaths.binaryName, environment: environment, currentDirectory: currentDirectory),
              URL(fileURLWithPath: first).resolvingSymlinksInPath().path == URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
        else { return ShellWord.quoted(binary) }
        return SiftPaths.binaryName
    }

    /// Whether the lookups block is to be added: yes without asking where a flag gave the answer, otherwise the answer to the question, which defaults to no after an earlier decline.
    ///
    /// A no is recorded and a yes, or a flag that adds the block, clears the record; an end of input is no answer and leaves it.
    private func wantsLookups(asking: Bool) -> Bool {
        let record = LookupsDeclineRecord(directory: stateDirectory, environment: environment)
        guard asking else {
            record.clear()
            return true
        }
        let declinedBefore = record.exists
        let answer = prompt.ask(AllowRunPrompt.lookupsQuestion(defaultingToNo: declinedBefore))
        let accepted = AllowRunPrompt.accepts(answer, defaultsTo: !declinedBefore)
        if accepted {
            record.clear()
        } else if answer != nil {
            record.write()
        }
        return accepted
    }

    /// Names any agent definition whose `tools:` allowlist would spawn contexts these hooks cannot reach.
    ///
    /// Here as well as in `status` because this is the moment the wiring is being done, and a hook installed into a machine that already holds such a definition is a hook that will be refusing lookups into a context holding nothing it names — for as long as it takes someone to wonder why the share is low. Silent when there is nothing to name, like everything else this prints.
    private static func emitAgentAllowlistNote(to output: CommandOutput) {
        // The repository, not the directory the installer happened to be run from: definitions live at
        // `<repo>/.claude/agents`, and an install run from a subdirectory would otherwise look in a
        // directory that does not exist and report that nothing is in scope.
        let root = CallerRoot.root(forCallerIn: FileManager.default.currentDirectoryPath)
        guard let text = AgentAllowlistReport.text(root: root) else { return }
        output.emit(text)
    }

    /// The binary as the first word of every command this registers: shell-quoted where its path holds a space or anything else a shell reads, because Claude Code runs each one through `sh -c`.
    private func executableWord() -> String {
        ShellWord.quoted(Self.binaryPath(invokedAs: arguments.first ?? SiftPaths.binaryName, environment: environment, executable: executable, names: names))
    }

    /// The refusal of a `binary` in npx's cache, which npx evicts, naming `rerun` as the command to run again from a lasting install.
    static func npxCacheRefusal(_ binary: String, rerun: String) -> ValidationError {
        ValidationError(
            "this \(ProductName.current.binary) is running from npx's cache (\(binary)), which npx evicts and replaces per version — hooks registered there would exit 127 after the next eviction. "
                + "Install the binary first (`brew install` or `install.sh`), then run `\(rerun)` from that install."
        )
    }

    /// The binary the hooks run: the path the shell found this one by, a link on PATH kept as the link, so the registration survives an install to a non-default `SWIFT_SURE_DEST` and a Homebrew upgrade.
    ///
    /// Never the bare name, which a hook's shell might resolve differently; the conventional install location only where nothing resolves at all.
    ///
    /// Run under a legacy name or an alias (and only one of `names` or `aliases`, so `sift-dev` is registered as it is), the binary records the current name's path when a sibling of that name sits beside it, so the hooks outlive the link. `names` is every name tried, current first.
    static func binaryPath(
        invokedAs argument0: String,
        environment: [String: String],
        executable: String?,
        names: [ProductName] = ProductName.recognised,
        aliases: [String] = ProductName.aliases
    ) -> String {
        let current = names.first ?? ProductName.current
        guard let running = InvokedBinary.runningPath(invokedAs: argument0, environment: environment, executable: executable) else {
            return AgentPaths.userHome(environment: environment).appendingPathComponent(".local/bin/\(current.binary)").path
        }
        let url = URL(fileURLWithPath: running)
        guard names.dropFirst().map(\.binary).contains(url.lastPathComponent) || aliases.contains(url.lastPathComponent) else { return running }
        let sibling = url.deletingLastPathComponent().appendingPathComponent(current.binary)
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling.path : running
    }
}

extension InstallHookCommand {
    /// Only the flags come off the command line; ``output`` and ``prompt`` keep their defaults on the parse path.
    enum CodingKeys: String, CodingKey {
        case settings
        case command
        case allowRun
        case allowLookups
        case agent
        case cursorDirectory
        case codexDirectory
    }

    /// The agent `install-hook` and `uninstall-hook` register with, and which of their flags each one takes.
    enum Agent: String, ExpressibleByArgument, CaseIterable, Sendable {
        case claude
        case cursor
        case codex

        /// The harness's name as a refusal spells it.
        var harness: String {
            switch self {
            case .claude:
                "Claude Code"
            case .cursor:
                "Cursor"
            case .codex:
                "Codex"
            }
        }

        /// Refuses a flag the chosen agent has no use for, so a `--settings` given with `--agent cursor` is never silently ignored.
        static func validate(_ agent: Agent, cursorDirectory: String?, codexDirectory: String?, claudeOnly: [String?]) throws {
            for (flag, owner) in [(cursorDirectory.map { _ in "--cursor-dir" }, Agent.cursor), (codexDirectory.map { _ in "--codex-dir" }, .codex)] {
                guard let flag, owner != agent else { continue }
                throw ValidationError("\(flag) applies only with --agent \(owner.rawValue)")
            }
            let given = claudeOnly.compactMap(\.self)
            guard agent != .claude, !given.isEmpty else { return }
            throw ValidationError(
                "\(given.joined(separator: ", ")) configure\(given.count == 1 ? "s" : "") Claude Code, not \(agent.harness) — drop \(given.count == 1 ? "it" : "them") with --agent \(agent.rawValue)"
            )
        }
    }
}
