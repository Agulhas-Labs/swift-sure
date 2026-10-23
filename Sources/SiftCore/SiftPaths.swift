//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Where SwiftSure keeps its files: the names it owns on disk, and the places they sit.
public struct SiftPaths {
    /// The directory the tool owns, both under `$HOME` and inside a repository.
    public static var directoryName: String {
        ProductName.current.directoryName
    }

    /// Every directory name this build owns or an earlier release left, the current name's first.
    ///
    /// What a walk skips and a scan treats as the tool's own. `names` is every name tried, current first.
    public static func directoryNames(names: [ProductName] = ProductName.recognised) -> [String] {
        names.map(\.directoryName)
    }

    /// The index database inside a cache directory.
    ///
    /// Named here because it is what makes a directory *the* cache: the tool writes other things beside it — `runs/`, the semantic store — and a directory holding only those is a directory the index is not in.
    public static var indexFileName: String {
        "index.db"
    }

    /// The executable's name.
    public static var binaryName: String {
        ProductName.current.binary
    }

    /// The per-repository configuration file.
    public static var configFileName: String {
        ProductName.current.configFileName
    }

    /// `~/.swift-sure` — one directory across every repository, since the usage log, the run log, the roots registry and the salt are all per-user rather than per-repo.
    public static var home: URL {
        home(environment: ProcessInfo.processInfo.environment)
    }

    /// `~/.swift-sure` under the home directory `environment` names, or the directory `SWIFT_SURE_HOME` names.
    ///
    /// `SWIFT_SURE_HOME` replaces the whole `~/.swift-sure` directory, so a probe or a worktree run can keep out of the user's roots registry, logs and advice ledger without moving `HOME`, which would hide the agent settings too. Honoured only when non-empty and absolute; anything else is unset.
    ///
    /// Without an override, the current name's directory when it exists, else the first legacy name's that does (used as it stands, never moved), else the current name's, for creating. `names` is every name tried, current first.
    public static func home(environment: [String: String], names: [ProductName] = ProductName.recognised) -> URL {
        if let override = EnvironmentVariable.home.value(in: environment, names: names), override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return existing(names, under: AgentPaths.userHome(environment: environment), isDirectory: true) { $0.directoryName }
    }

    /// `~/.swift-sure/callers` — where the `PreToolUse` hook leaves the identity of the context about to make an index call, for the server to stamp onto the log line.
    ///
    /// Per-user like the logs, and for the same reason: one server serves every repository a session touches, and the hook that names the caller has nothing repository-shaped to key on.
    public static var callers: URL {
        home.appendingPathComponent("callers", isDirectory: true)
    }

    /// `<repoRoot>/.swift-sure` — this repository's index cache, its run logs, and its semantic store.
    ///
    /// The current name's directory when it exists, else the first legacy name's that does, else the current name's, for creating. `names` is every name tried, current first.
    public static func cache(in repoRoot: URL, names: [ProductName] = ProductName.recognised) -> URL {
        existing(names, under: repoRoot, isDirectory: true) { $0.directoryName }
    }

    /// `<repoRoot>/.swift-sure.json` — this repository's configuration file, whether or not it exists.
    ///
    /// Resolved like ``cache(in:names:)``: the first name whose file exists, else the current name's.
    public static func config(in repoRoot: URL, names: [ProductName] = ProductName.recognised) -> URL {
        existing(names, under: repoRoot, isDirectory: false) { $0.configFileName }
    }

    /// The first of `names` whose `spelling` exists under `parent` as a directory (`isDirectory`) or as anything but one, else the first name's; nothing is moved or renamed.
    private static func existing(_ names: [ProductName], under parent: URL, isDirectory: Bool, spelling: (ProductName) -> String) -> URL {
        let candidates = (names.isEmpty ? [ProductName.current] : names).map { parent.appendingPathComponent(spelling($0), isDirectory: isDirectory) }
        return candidates.first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && directory.boolValue == isDirectory
        } ?? candidates[0]
    }
}
