//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The uninstall's MCP step: every server named `swift-sure` that Claude Code will start — the user-scope one `install.sh` registers, a local-scope one per project, a project's `.mcp.json` — and which of them run this tool.
///
/// The user-scope server and each local-scope one are taken out through `claude mcp remove`, a local-scope one from its project's directory and only where that directory is there under the very path Claude Code keys it by, which a linked worktree's is not; any other registration of this tool, a repository's `.mcp.json` included, is named with how to remove it and counted as not removed, and a server of the same name that runs something else is named and left alone.
struct UninstallServers {
    /// The package an earlier release's npm install ran through `npx`.
    static var npmPackage: String {
        SiftClaudeSetup.npmPackage
    }

    /// What the step removed, one answer line each.
    var removed: [String] = []
    /// What it named and did not remove, and why.
    var notes: [String] = []
    /// How many of the registrations it names as this tool's were not removed.
    var failures = 0
    /// The name whose server the step is settling.
    private var name = ProductName.current
    /// Whether the files that are read whatever the name were already checked, so a second name does not count them again.
    private var checkedFiles = false
    /// Each `.mcp.json` named as registering this tool, with for each server it names where its note is in `notes`, the server's name and the command it runs.
    private var ownProjectFiles: [String: [ProjectFileNote]] = [:]

    /// Takes out the user-scope and local-scope servers that run this tool, reading the config again after each so the answer says one went only if it did, and names every other `swift-sure` server in the config and in the `.mcp.json` of each of `roots`.
    ///
    /// Once for every name in `names`, current first: a server an earlier release registered under its own name goes the same way, its removal asked of the legacy-name closure with that name. `gitDirectories` is the question put to the repository before a local-scope removal, whether the project is a linked worktree; a test answers it without a repository.
    static func settle(
        _ locations: SiftUninstall.Locations,
        roots: [String],
        names: [ProductName] = ProductName.recognised,
        gitDirectories: (URL) throws -> (own: URL, common: URL)? = { try GitContext.askedDirectories(of: $0, within: nil) },
        removeLegacyServer: (ProductName, SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval = { _, _ in .noClaude },
        removeServer: (SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval
    ) -> UninstallServers {
        var step = UninstallServers()
        for (index, name) in names.enumerated() {
            step.name = name
            step.settleOne(locations, roots: roots, gitDirectories: gitDirectories, removeServer: index == 0 ? removeServer : { removeLegacyServer(name, $0) })
        }
        return step
    }

    /// The step for the one name in ``name``.
    private mutating func settleOne(
        _ locations: SiftUninstall.Locations,
        roots: [String],
        gitDirectories: (URL) throws -> (own: URL, common: URL)?,
        removeServer: (SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval
    ) {
        let config = locations.claudeConfig
        let removal = SiftClaudeSetup.server(named: name).removalCommand
        // An unreadable config would otherwise read as nothing registered, which is a claim nothing checked.
        if !checkedFiles, PathKind.of(config) != .absent, Self.jsonObject(at: config) == nil {
            failures += 1
            notes.append("mcp: not checked — \(config.path) could not be read as a JSON object; if \(name.mcpServer) is registered there, run: \(removal)")
        }
        switch Self.userServer(in: config, named: name) {
        case nil:
            break
        case let entry? where !entry.ours:
            notes.append("mcp: the user-scope server named \(name.mcpServer) runs \(entry.command), \(Self.foreign) — left alone")
        case let entry?:
            removeUser(entry, config: config, removeServer: removeServer)
        }
        for (project, entry) in Self.localServers(in: config, named: name) {
            if entry.ours {
                removeLocal(project, entry, config: config, gitDirectories: gitDirectories, removeServer: removeServer)
            } else {
                notes.append("mcp: the local-scope server named \(name.mcpServer) in \(project) runs \(entry.command), \(Self.foreign) — left alone")
            }
        }
        // A `.mcp.json` that is there and cannot be read or parsed would otherwise read as naming no server, which is a claim nothing checked.
        for file in checkedFiles ? [] : Self.unreadableProjectFiles(in: roots) {
            failures += 1
            notes.append("mcp: not checked — \(file) could not be read as a JSON object; if it registers \(name.mcpServer), remove that entry by hand")
        }
        for (file, entry) in Self.projectServers(in: roots, named: name) {
            if entry.ours {
                failures += 1
                ownProjectFiles[file, default: []].append(ProjectFileNote(note: notes.count, server: name.mcpServer, command: entry.command))
                notes.append(Self.projectFileNote(file, server: name.mcpServer, command: entry.command, unrecorded: false))
            } else {
                notes.append("mcp: \(file) names a server \(name.mcpServer) that runs \(entry.command), \(Self.foreign) — left alone")
            }
        }
        checkedFiles = true
    }

    /// Adds to the note on each named `.mcp.json` in one of `roots` that a later run will not find it, since the purge deleted the record naming its repository: one line per file, the one that says what to do.
    mutating func markUnrecorded(_ roots: [String]) {
        for root in roots {
            let file = Self.mcpJSON(in: root).path
            for own in ownProjectFiles[file] ?? [] {
                notes[own.note] = Self.projectFileNote(file, server: own.server, command: own.command, unrecorded: true)
            }
        }
    }

    /// The note on a repository's `.mcp.json` that registers this tool, which is never edited; `unrecorded` when no record left names its repository.
    private static func projectFileNote(_ file: String, server: String, command: String, unrecorded: Bool) -> String {
        let note = "mcp: not removed — \(file) registers \(server) (\(command)) for everyone who opens that repository; it is the repository's own file, so remove its \(server) entry by hand"
        return unrecorded ? note + ": the purge deleted the record naming its repository, so a later `\(ProductName.current.binary) uninstall` will not find it" : note
    }

    /// The `.mcp.json` of the repository at `root`.
    static func mcpJSON(in root: String) -> URL {
        URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(".mcp.json")
    }

    /// What a server of this name that runs something else is: not one this tool can tell is its own, which is all that was checked.
    private static var foreign: String {
        "not a registration \(ProductName.current.binary) recognises"
    }

    /// Takes this tool's user-scope server out through `claude mcp remove`, and reads every server entry back against how they stood just before, so it is reported removed only when it went and nothing else changed.
    private mutating func removeUser(_ entry: Entry, config: URL, removeServer: (SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval) {
        let removal = SiftClaudeSetup.server(named: name).removalCommand
        guard let before = McpRegistrations(config: config) else {
            failures += 1
            notes.append("mcp: not removed — \(config.path) could not be read just before `\(removal)` would run, so it was not run; run it yourself")
            return
        }
        switch removeServer(.user) {
        case .removed:
            switch McpRegistrations.readBack(config, before: before, target: McpRegistrations.key(project: nil, name: name.mcpServer)) {
            case .removed:
                removed.append("mcp: removed the user-scope server — \(entry.command)")
            case .stillRegistered:
                failures += 1
                notes.append("mcp: not removed — `\(removal)` succeeded and the server is still registered (\(config.path))")
            case .unreadable:
                failures += 1
                notes.append("mcp: not removed — `\(removal)` succeeded and \(config.path) could not be read back, so whether the server went is not known")
            case let .othersChanged(others, gone):
                failures += 1
                notes.append(Self.othersChanged(others, targetGone: gone, command: "`\(removal)` ran", config: config))
            }
        case let .failed(reason):
            failures += 1
            notes.append("mcp: not removed — `\(removal)` failed: \(reason)")
        case .noClaude:
            failures += 1
            notes.append("mcp: not removed — `claude` is not on PATH; run: \(removal)")
        }
    }

    /// Takes this tool's local-scope server in `project` out by running `claude mcp remove` in that directory, only where it is a directory whose resolved path is `project` itself, is not inside a git repository rooted elsewhere and is not a linked worktree, so the entry Claude Code finds from there is the one read here; anything else is named with how to remove it by hand and counted, and so is a removal during which any other entry changed.
    private mutating func removeLocal(_ project: String, _ entry: Entry, config: URL, gitDirectories: (URL) throws -> (own: URL, common: URL)?, removeServer: (SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval) {
        let directory = URL(fileURLWithPath: project, isDirectory: true)
        let command = (["claude"] + SiftUninstall.ServerScope.local(directory).removalArguments(for: name)).joined(separator: " ")
        let byHand = "remove projects[\"\(project)\"].mcpServers.\(name.mcpServer) from \(config.path) by hand"
        let resolved = BinaryRemoval.resolvedPath(project)
        guard project.hasPrefix("/"), PathKind.of(directory) == .directory, resolved == project else {
            failures += 1
            var isDirectory: ObjCBool = false
            let throughALink = project.hasPrefix("/") && FileManager.default.fileExists(atPath: project, isDirectory: &isDirectory) && isDirectory.boolValue
            let why = throughALink
                ?"that path resolves to \(resolved), so `\(command)` run there could reach another project's entry"
                : "\(project) is not a directory here, so `\(command)` cannot be run from it"
            notes.append("mcp: not removed — the local-scope server in \(project) runs \(entry.command); \(why): \(byHand)")
            return
        }
        // Claude Code keys a local-scope server anywhere in a linked worktree by the main repository, so this goes first, for the worktree's root and every directory under it; a submodule, whose two git directories are one, it keys by its own root.
        // A git that does not answer cannot say whether this is a linked worktree, and a removal run in one reaches the main repository's entry before anything can report it.
        let git: (own: URL, common: URL)?
        do {
            git = try gitDirectories(directory)
        } catch {
            failures += 1
            let prefix = "mcp: not removed — the local-scope server in \(project) runs \(entry.command); "
            if let engineError = error as? EngineError, case .gitDidNotAnswer = engineError {
                notes.append(prefix + "\(error) Until it does, `\(command)` is not run there, since it could reach another root's entry: \(byHand)")
            } else {
                notes.append(prefix + "could not ask git whether \(project) is a linked worktree (\(error)); the local-scope entry is left alone: \(byHand)")
            }
            return
        }
        if let git, git.own != git.common {
            failures += 1
            notes.append("mcp: not removed — the local-scope server in \(project) runs \(entry.command); \(project) is in a linked git worktree (its repository's shared git directory is \(CanonicalPath.of(git.common.path))), and Claude Code keys a worktree's local-scope server by the main repository, so `\(command)` run there would reach the main repository's entry: \(byHand)")
            return
        }
        // Claude Code keys a local-scope server by the git root of the directory it runs in, so from inside another repository's tree it would reach that root's entry.
        // A git that does not answer leaves that root unknown, and an unknown root is not one known to be the project's own.
        let enclosing: URL?
        do {
            enclosing = try GitContext.enclosingRoot(from: directory)
        } catch {
            failures += 1
            notes.append("mcp: not removed — the local-scope server in \(project) runs \(entry.command); \(error) Until it does, `\(command)` is not run there, since it could reach another root's entry: \(byHand)")
            return
        }
        if let root = enclosing.map({ CanonicalPath.of($0.path) }), root != project {
            failures += 1
            notes.append("mcp: not removed — the local-scope server in \(project) runs \(entry.command); \(project) is inside the git repository at \(root), and claude keys a local-scope server by that root, so `\(command)` run there would reach \(root)'s entry: \(byHand)")
            return
        }
        guard let before = McpRegistrations(config: config) else {
            failures += 1
            notes.append("mcp: not removed — \(config.path) could not be read just before `\(command)` would run in \(project), so it was not run: \(byHand)")
            return
        }
        switch removeServer(.local(directory)) {
        case .removed:
            let target = McpRegistrations.key(project: project, name: name.mcpServer)
            switch McpRegistrations.readBack(config, before: before, target: target) {
            case .removed:
                removed.append("mcp: removed the local-scope server in \(project) — \(entry.command)")
            case .stillRegistered:
                failures += 1
                notes.append("mcp: not removed — `\(command)` run in \(project) succeeded and the server is still registered (\(config.path))")
            case .unreadable:
                failures += 1
                notes.append("mcp: not removed — `\(command)` run in \(project) succeeded and \(config.path) could not be read back, so whether the server went is not known")
            case let .othersChanged(others, gone):
                failures += 1
                notes.append(Self.othersChanged(others, targetGone: gone, command: "`\(command)` ran in \(project)", config: config))
            }
        case let .failed(reason):
            failures += 1
            notes.append("mcp: not removed — `\(command)` run in \(project) failed: \(reason)")
        case .noClaude:
            failures += 1
            notes.append("mcp: not removed — `claude` is not on PATH; from \(project) run: \(command)")
        }
    }

    /// The note for a removal during which entries other than its own changed: not counted as removed, since `claude` may have taken out the wrong one, with the entries to check.
    static func othersChanged(_ others: [String], targetGone: Bool, command: String, config: URL) -> String {
        let which = others.joined(separator: ", ")
        let target = targetGone ? "the \(ProductName.current.mcpServer) entry went too" : "the \(ProductName.current.mcpServer) entry is still there"
        return "mcp: not removed — while \(command), \(which) changed in \(config.path) as well (\(target)); claude may have removed the wrong entry, so check \(others.count == 1 ? "that entry" : "those entries") there"
    }

    /// The user-scope server named `swift-sure` in Claude Code's config.
    static func userServer(in config: URL, named name: ProductName = .current) -> Entry? {
        entry((jsonObject(at: config)?["mcpServers"] as? [String: Any])?[name.mcpServer], named: name)
    }

    /// Every project with a local-scope server named `swift-sure`, in path order.
    static func localServers(in config: URL, named name: ProductName = .current) -> [(project: String, entry: Entry)] {
        guard let projects = jsonObject(at: config)?["projects"] as? [String: Any] else { return [] }
        return projects.compactMap { path, value in
            let servers = (value as? [String: Any])?["mcpServers"] as? [String: Any]
            return entry(servers?[name.mcpServer], named: name).map { (path, $0) }
        }
        .sorted { $0.project < $1.project }
    }

    /// Every `.mcp.json` in `roots` that names a server `swift-sure`: read only, since the file is the repository's and is shared with everyone who clones it.
    static func projectServers(in roots: [String], named name: ProductName = .current) -> [(file: String, entry: Entry)] {
        roots.compactMap { root in
            let file = mcpJSON(in: root)
            return entry((jsonObject(at: file)?["mcpServers"] as? [String: Any])?[name.mcpServer], named: name).map { (file.path, $0) }
        }
    }

    /// Every `.mcp.json` in `roots` that exists and cannot be read as a JSON object; a missing one is not among them.
    static func unreadableProjectFiles(in roots: [String]) -> [String] {
        roots.compactMap { root in
            let file = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(".mcp.json")
            return PathKind.of(file) != .absent && jsonObject(at: file) == nil ? file.path : nil
        }
    }

    /// A server entry, as the command it runs and whether that is a registration this tool's own docs make.
    static func entry(_ value: Any?, named name: ProductName = .current) -> Entry? {
        guard let value = value as? [String: Any] else { return nil }
        let command = value["command"] as? String ?? ""
        let arguments = value["args"] as? [String] ?? []
        return Entry(command: ([command] + arguments).joined(separator: " "), ours: recognises(command: command, arguments: arguments, named: name))
    }

    /// Whether `command` run with `arguments` is this tool's MCP server as `install.sh` or an earlier release's npm install registers it: an executable named `swift-sure` run with `mcp` alone, or `npx` running this package's `mcp`.
    ///
    /// Anything else — a path that merely contains the name, another package whose name starts with this one's, other arguments — is someone else's.
    static func recognises(command: String, arguments: [String], named name: ProductName = .current) -> Bool {
        let program = URL(fileURLWithPath: command).lastPathComponent
        if program == name.binary, arguments == ["mcp"] {
            return true
        }
        if program == "npx", npxRunsServer(arguments) {
            return true
        }
        return false
    }

    /// `npx` arguments that run this package's `mcp` and nothing else: `-y` or `--yes` any number of times, the package (optionally at a version), then `mcp`.
    private static func npxRunsServer(_ arguments: [String]) -> Bool {
        let rest = arguments.drop { $0 == "-y" || $0 == "--yes" }
        guard rest.count == 2, rest.last == "mcp", let package = rest.first else { return false }
        return package == npmPackage || package.hasPrefix(npmPackage + "@")
    }

    static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

extension UninstallServers {
    /// One server entry named `swift-sure`: the command it runs, spelled as a person would type it, and whether it is this tool's.
    struct Entry: Equatable {
        let command: String
        let ours: Bool
    }
}

extension UninstallServers {
    /// Where a `.mcp.json`'s note on one server is in `notes`, the server's name and the command it runs.
    private struct ProjectFileNote {
        let note: Int
        let server: String
        let command: String
    }
}
