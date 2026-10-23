//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// `swift-sure uninstall` — takes out everything `install.sh` and `install-hook` put in, lists every `.swift-sure/` directory the tool knows it left, and deletes those only when asked.
///
/// What goes: the hooks, allow rules and status line in the Claude Code settings file (``HookUninstall``), the MCP server `install.sh` registers at user scope and the README's at local scope, the band plugin and its marketplace (`UninstallBand`), and the agent rule it copied into `~/.claude/rules`. What is listed: each repository's `.swift-sure/` that the roots registry or the usage and run logs name, and `~/.swift-sure` itself, which holds those logs, then the settings file's `.bak-swift-sure` copy, which can still hold the hooks; `purge` deletes them. The binary is never touched — a running binary does not delete itself — so the answer ends with the one line that removes it. Everything is read before anything is deleted, since the record of which repositories hold a cache lives in the directory a purge removes last.
public struct SiftUninstall {
    /// Runs the uninstall and returns its answer, one line per element — the verdict, what was removed, the directories purged or left, what was left alone and why, and what removes `binary` (an `rm`, or the uninstall of the package manager that put it there) — with how many things it could not take out.
    ///
    /// `names` is every name whose registrations come out, current first; the closure given for legacy names removes a server registered under one of the others. `removeServer` is called for each server named `swift-sure` that runs this tool — the user-scope one, and a local-scope one in each project directory that is there — and the registration is read again afterwards, so the answer says it went only if it did. `band` runs `claude` with the arguments it is given, for the Claude Code plugin `install.sh` enables, and is called only where the settings file registers it. A skipped band step runs none of it: `claude plugin` edits the user's own settings, so against a settings file named by the caller it would read one file and change another.
    public static func run(
        _ locations: Locations,
        purge: Bool,
        binary: String,
        codex: any CodexMcpRunner,
        bandSkipped: Bool = false,
        removeServer: (ServerScope) -> ServerRemoval,
        names: [ProductName] = ProductName.recognised,
        removeLegacyServer: (ProductName, ServerScope) -> ServerRemoval = { _, _ in .noClaude },
        band: ([String]) -> PluginRun = { _ in .noClaude }
    ) throws -> Answer {
        let (roots, skipped) = recordedRoots(locations)
        let caches = leftCaches(locations, roots: roots, names: names)

        var removed: [String] = []
        var count = 0
        var notes: [String] = []
        var failures = 0
        if skipped > 0 {
            let which = skipped == 1
                ? "1 recorded root is not an absolute path, so no \(ProductName.current.directoryName) under it"
                : "\(skipped) recorded roots are not absolute paths, so no \(ProductName.current.directoryName) under them"
            notes.append("skipped: \(which) was looked for")
        }

        let before = try? Data(contentsOf: locations.settings)
        var hooksChanged = false
        do {
            let hooks = try HookUninstall.run(settings: locations.settings, onlyAdvice: false, names: names)
            hooksChanged = hooks.changed
            if hooks.changed {
                removed += hooks.removed
                count += hooks.removed.count
                removed.append("      \(SettingsFile.named(locations.settings))")
            }
            if let statusline = hooks.statusline, statusline.hasPrefix("statusline: not ours") {
                notes.append(statusline)
            }
            if let backupNote = hooks.backupNote {
                notes.append(backupNote)
            }
        } catch let unreadable as HookUninstall.Unreadable {
            failures += 1
            notes.append(unreadable.description)
        } catch let unwritten as SettingsFile.Unwritten {
            failures += 1
            notes.append("hooks: not removed — \(unwritten.path): \(unwritten.reason)")
        } catch {
            failures += 1
            // A read that fails throws `Unreadable` and a rewrite that fails `Unwritten`, both caught above, so anything
            // else is a file that could not be parsed, never looked into, so whether the hooks are there is not known.
            let detail = (error as? HookRegistrationError)?.description ?? error.localizedDescription
            notes.append("hooks: not checked — \(locations.settings.path) could not be read as settings: \(detail)")
        }
        // Read only now, since the hooks step is what writes it; it is this run's copy only if it holds what that step read.
        // The copy sits beside the file the hooks step rewrote, which for a symlinked settings path is the file it leads to.
        let backupURL = SettingsBackupFile.url(beside: (try? SettingsFile.target(of: locations.settings)) ?? locations.settings, tool: .sift)
        let settingsFresh = hooksChanged && before != nil && (try? Data(contentsOf: backupURL)) == before
        var backups = [(noun: "settings", backup: settingsBackup(backupURL, noun: "settings", ours: "hooks", purge: purge, fresh: settingsFresh))]
        if case let .refused(note) = backups[0].backup {
            failures += 1
            notes.append(note)
        }

        var servers = UninstallServers.settle(locations, roots: roots, names: names, removeLegacyServer: removeLegacyServer, removeServer: removeServer)
        removed += servers.removed
        count += servers.removed.count
        let serverNotes = notes.endIndex ..< notes.endIndex + servers.notes.count
        notes += servers.notes
        failures += servers.failures

        if bandSkipped {
            notes.append("the band step was skipped: --settings names a file other than the user's settings, which is what `claude plugin` edits")
        } else {
            let bandStep = UninstallBand.settle(settings: locations.settings, claude: band)
            removed += bandStep.removed
            count += bandStep.removed.count
            notes += bandStep.notes
            failures += bandStep.failures
        }

        let agentFiles = BackedUpFile.agents(locations)
        let cursor = cursorStep(locations.cursor)
        removed += cursor.outcome.lines + cursor.outcome.written.map { "      \($0)" }
        count += cursor.outcome.lines.count
        notes += cursor.outcome.notes
        if let failure = cursor.failure {
            failures += 1
            notes.append(failure)
        }
        let codexOutcome = codexStep(locations.codex, runner: codex)
        removed += codexOutcome.outcome.lines + codexOutcome.outcome.written.map { "      \($0)" }
        count += codexOutcome.outcome.lines.count
        notes += codexOutcome.outcome.notes + codexOutcome.outcome.failures + [codexOutcome.failure].compactMap(\.self)
        failures += codexOutcome.outcome.failures.count + (codexOutcome.failure == nil ? 0 : 1)
        for file in agentFiles {
            let backup = file.backup(purge: purge)
            if case let .refused(note) = backup {
                failures += 1
                notes.append(note)
            }
            backups.append((file.noun, backup))
        }

        // The rule, then the copy of a differing rule `swift-sure install` kept beside it before replacing it, and the same pair under each earlier name.
        for rule in locations.ruleFiles {
            do {
                switch try removeRule(at: rule) {
                case let .removed(line):
                    removed.append(line)
                    count += 1
                case let .left(note):
                    notes.append(note)
                case nil:
                    break
                }
            } catch {
                failures += 1
                notes.append("rule: not removed — \(rule.path): \(error.localizedDescription)")
            }
        }

        var directories = UninstallPurge.settle(caches, purge: purge)
        if purge {
            directories.settleAftermath(locations, roots: roots)
            // A `.mcp.json` a later run cannot find says so on the line already naming it, in its place.
            servers.markUnrecorded(directories.unrecorded)
            notes.replaceSubrange(serverNotes, with: servers.notes)
        }
        let purged = directories.purged
        let left = directories.left
        notes += directories.notes
        failures += directories.failures

        let deletedBackups = backups.filter { $0.backup?.deleted == true }.map(\.noun)
        let purgedLedgers = purged.filter(directories.ledgers.contains).count
        var lines = [verdict(failures: failures, removed: count, purged: (purged.count - purgedLedgers, purgedLedgers), deletedBackups: deletedBackups)]
        lines += removed
        lines += purged.map { "purged: \($0)" }
        lines += left.map { "left: \($0)" }
        if !left.isEmpty {
            let gone = left.contains(where: directories.ledgers.contains) ? "the usage and run logs, and the run proofs the ledgers record, are" : "the usage and run logs are"
            lines.append("      `\(ProductName.current.binary) uninstall --purge` deletes \(left.count == 1 ? "it" : "them"): the indexes rebuild on the next query; \(gone) gone for good")
        }
        lines += backups.compactMap { $0.backup?.line }
        lines += notes
        lines.append("binary: \(BinaryRemoval.line(for: binary))")
        return Answer(lines: lines, failures: failures)
    }

    /// Takes this tool's registrations out of the Cursor directory, silent when it holds none: what went, or the line saying why it could not be checked or rewritten.
    static func cursorStep(_ directory: URL?) -> (outcome: InstallOutcome, failure: String?) {
        guard let directory else { return (InstallOutcome(lines: [], notes: [], written: []), nil) }
        return agentStep("cursor") {
            var outcome = try SiftCursorSetup.install.uninstall(directory: directory)
            let legacy = try LegacyCursorCleanup.settle(directory: directory, installing: false, written: outcome.written)
            outcome.lines += legacy.lines
            outcome.notes += legacy.notes
            outcome.written += legacy.written.filter { !outcome.written.contains($0) }
            return outcome
        }
    }

    /// Takes this tool's hooks and server out of the Codex home, silent when it holds none, as ``cursorStep(_:)`` does for Cursor.
    static func codexStep(_ home: CodexInstall.Home?, runner: any CodexMcpRunner) -> (outcome: InstallOutcome, failure: String?) {
        guard let home else { return (InstallOutcome(lines: [], notes: [], written: []), nil) }
        return agentStep("codex") { try CodexInstall.uninstall(home: home, runner: runner) }
    }

    /// One agent's uninstall, a refusal or a failed rewrite turned into the line naming it.
    private static func agentStep(_ agent: String, _ body: () throws -> InstallOutcome) -> (outcome: InstallOutcome, failure: String?) {
        let nothing = InstallOutcome(lines: [], notes: [], written: [])
        do {
            return try (body(), nil)
        } catch let refused as SettingsFile.Refused {
            return (nothing, refused.description)
        } catch let unwritten as SettingsFile.Unwritten {
            return (nothing, "\(agent): not removed — \(unwritten.path): \(unwritten.reason)")
        } catch {
            return (nothing, "\(agent): not removed — \(error.localizedDescription)")
        }
    }

    /// The verdict line: what could not be done first, then what was.
    private static func verdict(failures: Int, removed: Int, purged: (caches: Int, ledgers: Int), deletedBackups: [String]) -> String {
        var parts: [String] = []
        if failures > 0 {
            parts.append("\(failures) not removed")
        }
        if removed > 0 {
            parts.append("removed \(removed) registration\(removed == 1 ? "" : "s")")
        }
        let directories = [(purged.caches, ProductName.current.directoryName), (purged.ledgers, "run-ledger")].filter { $0.0 > 0 }
        if !directories.isEmpty {
            parts.append("purged " + directories.map { "\($0.0) \($0.1) director\($0.0 == 1 ? "y" : "ies")" }.joined(separator: " and "))
        }
        if let last = deletedBackups.last {
            let nouns = deletedBackups.count == 1 ? last : deletedBackups.dropLast().joined(separator: ", ") + " and " + last
            parts.append("deleted the \(nouns) backup\(deletedBackups.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "uninstall: nothing to do" : "uninstall: \(parts.joined(separator: ", "))"
    }

    /// The copy of a file this tool's install and uninstall write beside it before a rewrite: deleted under `purge` when it is a plain file, listed otherwise, and never followed through a link.
    ///
    /// `noun` is what the answer calls the file's contents ("settings") and `ours` what of this tool's it held ("hooks"); `fresh` says the copy is the one this run's rewrite wrote, the only case in which the answer can say it holds what was just removed.
    static func settingsBackup(_ backup: URL, noun: String, ours: String, purge: Bool, fresh: Bool) -> SettingsBackup? {
        let path = backup.path
        let reason: String
        switch PathKind.of(backup) {
        case .absent:
            return nil
        case .file where purge:
            do {
                try FileManager.default.removeItem(at: backup)
            } catch {
                return .refused("not purged: \(path) — \(error.localizedDescription)")
            }
            return PathKind.of(backup) == .absent ? .deleted("backup: deleted \(path)") : .refused("not purged: \(path) — still there after the delete")
        case .file:
            let holds = fresh
                ? "the \(noun) as they were before this uninstall, \(ProductName.current.binary)'s \(ours) included"
                : "a copy of the \(noun) from before \(ProductName.current.binary) last rewrote them"
            return .listed("backup: \(path) — \(holds); `\(ProductName.current.binary) uninstall --purge` deletes it")
        case let .symlink(target):
            reason = "a symlink to \(target ?? "an unreadable target"), not a file"
        case .directory, .other:
            reason = "not a plain file"
        }
        return purge ? .refused("not purged: \(path) is \(reason) — remove it by hand") : .listed("backup: \(path) is \(reason) — left as is")
    }

    /// Every repository the roots registry or the logs name, canonical and once each however many spellings reached it, with how many recorded roots were skipped.
    ///
    /// A recorded root that is not an absolute path is skipped and counted, never resolved: against wherever this runs it would name a directory the tool never recorded. Every step that looks under a recorded repository — the caches and the `.mcp.json` files — takes its roots from here.
    static func recordedRoots(_ locations: Locations) -> (roots: [String], skipped: Int) {
        let registry = RootsRegistry(fileURL: RootsRegistry.fileURL(in: locations.siftHome))
        let recorded = Set(registry.recordedRoots()).union(RootsRegistry.roots(inLogsAt: locations.logs))
        let absolute = recorded.filter { $0.hasPrefix("/") }
        return (Set(absolute.map(CanonicalPath.of)).sorted(), recorded.count - absolute.count)
    }

    /// Every directory of a recognised name on disk under `roots`, and each of their repositories' run-ledger directories under its git common directory, then `~/.swift-sure` itself.
    static func leftCaches(_ locations: Locations, roots: [String], names: [ProductName] = ProductName.recognised) -> [LeftCache] {
        let home = CanonicalPath.of(locations.siftHome.path)
        // `~/.swift-sure` itself as a path, its last component unresolved: a recorded home names the same entry, link or not, and it is listed once, below.
        let homeEntry = URL(fileURLWithPath: CanonicalPath.of(locations.siftHome.deletingLastPathComponent().path)).appendingPathComponent(locations.siftHome.lastPathComponent).path
        var caches: [LeftCache] = []
        var ledgers: Set<String> = []
        for root in roots {
            let repository = URL(fileURLWithPath: root, isDirectory: true)
            for name in names {
                let directory = repository.appendingPathComponent(name.directoryName, isDirectory: true)
                let kind = PathKind.of(directory)
                guard kind != .absent, directory.path != homeEntry, kind != .directory || CanonicalPath.of(directory.path) != home else { continue }
                caches.append(LeftCache(directory: directory, repository: repository, refusal: kind.refusal))
            }
            // Where `RunLedger.inRepository` writes the run ledgers every worktree shares: listed once however many of its worktrees were recorded.
            // Spelled as the repositories' caches are, where git's answer drops a leading `/private`.
            guard let common = GitContext.commonDirectory(of: repository).map({ CanonicalPath.of($0.path) }) else { continue }
            for spelling in Set(names.map(RunLedger.sharedDirectoryName(of:))).sorted() {
                let directory = URL(fileURLWithPath: common, isDirectory: true).appendingPathComponent(spelling, isDirectory: true)
                // A file of that name is another tool's, with nothing of this one's to purge; a link is listed and refused, as a repository's is.
                let kind = PathKind.of(directory)
                switch kind {
                case .directory, .symlink:
                    guard ledgers.insert(directory.path).inserted else { continue }
                case .absent, .file, .other:
                    continue
                }
                caches.append(LeftCache(directory: directory, repository: nil, refusal: kind.refusal, ledger: true))
            }
        }
        // Read without following a link, as the repositories' are: a delete through a linked `~/.swift-sure` would empty its target.
        // A home a variable moved is deleted whole only while it holds nothing but what this tool writes there, so a mis-set variable cannot empty a directory of the user's.
        let homeKind = PathKind.of(locations.siftHome)
        if homeKind != .absent {
            let refusal = homeKind.refusal ?? locations.homeOverride.flatMap { foreignEntriesRefusal(in: locations.siftHome, namedBy: $0) }
            caches.append(LeftCache(directory: locations.siftHome, repository: nil, refusal: refusal, movedBy: locations.homeOverride))
        }
        return caches
    }

    /// Deletes the rule `install.sh` copied in, or leaves a symlink where it is, as `install.sh` does: a link means the rule is a checkout's own file, which the install never wrote.
    static func removeRule(at url: URL) throws -> RuleRemoval? {
        let path = url.path
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType else {
            return nil
        }
        guard type != .typeSymbolicLink else {
            let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? "an unreadable target"
            return .left("rule: \(path) is a symlink to \(target) — left as is")
        }
        try FileManager.default.removeItem(atPath: path)
        return .removed("rule: removed \(path)")
    }
}

public extension SiftUninstall {
    /// Every path the uninstall reads or changes, built from one environment so a test or a probe moves all of them at once.
    struct Locations: Sendable {
        /// The Claude Code settings file the hooks and status line are in.
        public var settings: URL
        /// Claude Code's own `.claude.json` — in `CLAUDE_CONFIG_DIR` when that is set, else the home — where `claude mcp add --scope user` records the server; read here, never written.
        public var claudeConfig: URL
        /// The agent rule `install.sh` copies in.
        public var rule: URL
        /// `~/.swift-sure`, the per-user directory holding the logs and the roots registry.
        public var siftHome: URL
        /// The variable that moved `siftHome` away from every name's default `~/.swift-sure`, or `nil` where it sits at one: a moved home is purged only while it holds nothing but what this tool writes there.
        public var homeOverride: String?
        /// The JSON-lines logs whose `root` fields name repositories this tool has run in.
        public var logs: [URL]
        /// The Cursor directory whose `mcp.json` and `hooks.json` `install-hook --agent cursor` writes, or `nil` to leave Cursor out of the run.
        public var cursor: URL?
        /// The Codex home whose `hooks.json` and MCP server `install-hook --agent codex` writes, or `nil` to leave Codex out of the run.
        public var codex: CodexInstall.Home?

        public init(settings: URL, claudeConfig: URL, rule: URL, siftHome: URL, homeOverride: String? = nil, logs: [URL], cursor: URL? = nil, codex: CodexInstall.Home? = nil) {
            self.settings = settings
            self.claudeConfig = claudeConfig
            self.rule = rule
            self.siftHome = siftHome
            self.homeOverride = homeOverride
            self.logs = logs
            self.cursor = cursor
            self.codex = codex
        }

        /// The rule file and the backup kept beside it, then the pair under each earlier name the rule was installed as, which sit in the same directory.
        var ruleFiles: [URL] {
            let directory = rule.deletingLastPathComponent()
            let earlier = ProductName.legacy.map(FieldworkTool.named)
            return [rule, SettingsBackupFile.url(beside: rule, tool: .sift)] + earlier.flatMap { tool -> [URL] in
                let file = directory.appendingPathComponent(tool.installedRuleName)
                return [file, SettingsBackupFile.url(beside: file, tool: tool)]
            }
        }

        /// The paths under the home `environment` names; the usage log comes from the caller because naming it is the server's job.
        public static func standard(environment: [String: String], usageLog: URL) -> Locations {
            Locations(
                settings: AgentPaths.claudeSettings(environment: environment),
                claudeConfig: AgentPaths.claudeConfig(environment: environment),
                rule: AgentPaths.claudeRule(named: FieldworkTool.sift.installedRuleName, environment: environment),
                siftHome: SiftPaths.home(environment: environment),
                homeOverride: homeOverride(in: environment),
                logs: [usageLog, RunUsageLog.standardFileURL(environment: environment)],
                cursor: AgentPaths.cursorDirectory(environment: environment),
                codex: CodexInstall.home(flag: nil, environment: environment)
            )
        }

        /// The variable that sets the home, read as ``SiftPaths/home(environment:names:)`` reads it, when it names an absolute directory other than every name's default under the user's home.
        static func homeOverride(in environment: [String: String], names: [ProductName] = ProductName.recognised) -> String? {
            guard let value = EnvironmentVariable.home.value(in: environment, names: names), value.hasPrefix("/") else { return nil }
            let personal = AgentPaths.userHome(environment: environment)
            let defaults = Set(names.map { CanonicalPath.of(personal.appendingPathComponent($0.directoryName).path) })
            guard !defaults.contains(CanonicalPath.of(value)) else { return nil }
            return names.map { $0.environmentVariable(EnvironmentVariable.home.rawValue) }.first { environment[$0] != nil }
        }
    }

    /// The uninstall's answer, and how many of the things it names it could not take out: the count its verdict leads with.
    struct Answer: Equatable, Sendable {
        public let lines: [String]
        public let failures: Int
    }

    /// What asking Claude Code to drop a server came to.
    enum ServerRemoval: Equatable, Sendable {
        case removed
        case failed(String)
        case noClaude
    }

    /// What running `claude plugin` came to.
    enum PluginRun: Equatable, Sendable {
        case succeeded
        case failed(String)
        case noClaude
    }

    /// Which registration of the server named `swift-sure` a removal is for.
    enum ServerScope: Equatable, Sendable {
        /// The one in `.claude.json` itself, which `claude mcp remove` reaches from anywhere.
        case user
        /// The one `.claude.json` keeps for the project at this directory, which `claude mcp remove` reaches only when run there.
        case local(URL)

        /// The arguments to `claude` that remove the server named `swift-sure` at this scope, exactly.
        public var removalArguments: [String] {
            removalArguments(for: .current)
        }

        /// The same, for the server registered under `name`.
        public func removalArguments(for name: ProductName) -> [String] {
            let user = SiftClaudeSetup.server(named: name).removalArguments.first ?? []
            return switch self {
            case .user:
                user
            case .local:
                Array(user.dropLast()) + ["local"]
            }
        }
    }
}

extension SiftUninstall {
    /// A directory the tool left, with the repository it caches for where it is that repository's `.swift-sure/`, or `nil` for one deleted outright: `~/.swift-sure`, or a repository's run ledgers under its git common directory.
    struct LeftCache: Equatable {
        let directory: URL
        let repository: URL?
        /// Why the purge will not delete it — a symlink, or not a directory — or `nil` when it will.
        let refusal: String?
        /// Whether it is a repository's run ledgers rather than a `.swift-sure/` directory.
        var ledger = false
        /// The variable that moved it, where it is the home and a variable put it away from `~/.swift-sure`: checked again just before the delete.
        var movedBy: String?
    }

    /// What became of the agent rule.
    enum RuleRemoval: Equatable {
        case removed(String)
        case left(String)
    }

    /// A Cursor or Codex file the uninstall may rewrite, read before it runs so that the `.bak-swift-sure` copy beside it afterwards can be told apart from an older one.
    struct BackedUpFile {
        let file: URL
        /// What the answer calls the file's contents, as ``settingsBackup(_:noun:ours:purge:fresh:)`` takes it.
        let noun: String
        /// What of this tool's the file held.
        let ours: String
        let before: Data?

        init(_ file: URL, noun: String, ours: String) {
            self.file = file
            self.noun = noun
            self.ours = ours
            before = try? Data(contentsOf: file)
        }

        /// The files the Cursor and Codex steps rewrite, each only where that agent is part of the run.
        static func agents(_ locations: Locations) -> [BackedUpFile] {
            var files: [BackedUpFile] = []
            if let cursor = locations.cursor {
                files.append(BackedUpFile(cursor.appendingPathComponent(CursorMcpFile.fileName), noun: "Cursor MCP servers", ours: "server"))
                files.append(BackedUpFile(cursor.appendingPathComponent(CursorHooksFile.fileName), noun: "Cursor hooks", ours: "hooks"))
            }
            if let codex = locations.codex {
                files.append(BackedUpFile(codex.directory.appendingPathComponent(CodexHooksFile.fileName), noun: "Codex hooks", ours: "hooks"))
            }
            return files
        }

        /// The copy beside the file a rewrite lands in, which for a symlink is the file it leads to, taken as this run's only when the file changed and the copy holds what it held before.
        ///
        /// Whether the file changed is read from its bytes rather than the step's answer, since a step that throws after one rewrite reports none.
        func backup(purge: Bool) -> SettingsBackup? {
            let backup = SettingsBackupFile.url(beside: (try? SettingsFile.target(of: file)) ?? file, tool: .sift)
            let rewritten = before != nil && (try? Data(contentsOf: file)) != before
            return settingsBackup(backup, noun: noun, ours: ours, purge: purge, fresh: rewritten && (try? Data(contentsOf: backup)) == before)
        }
    }

    /// What became of a backup, as the line that says so.
    enum SettingsBackup: Equatable {
        case deleted(String)
        case listed(String)
        /// Asked to delete it and did not: counted with what was not removed.
        case refused(String)

        var deleted: Bool {
            if case .deleted = self {
                return true
            }
            return false
        }

        /// The line among the listings, or `nil` for a refusal, which goes with the notes.
        var line: String? {
            switch self {
            case let .deleted(line), let .listed(line):
                line
            case .refused:
                nil
            }
        }
    }
}
