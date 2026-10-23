//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Cursor's own shell permission rules, read into the same shape as Claude Code's, so the hook can tell whether a build rewritten in place to `swift-sure run -- …` meets a prompt the line as written would not.
///
/// Cursor's CLI keeps its rules in `cli-config.json` under the user's `~/.cursor` and in a project's `.cursor/cli.json`, each a `permissions` object with `allow` and `deny` lists. Only the `Shell(…)` entries speak for a shell command: `Shell(base)` matches a command line by its first word, and `Shell(base:args)` matches the first word and the arguments with globs. Deny entries keep the rewrite from being made, as ask and deny rules do on Claude Code; allow entries decide whether the rewrite adds a prompt.
///
/// Cursor applies its own approval to the rewritten command, so the reading only has to keep the rewrite from routing a build around a rule the user wrote for the build as written. The IDE's own allowlist lives in no file the hook reads, and is not consulted.
public struct CursorShellPermission {
    /// The rules Cursor applies to a shell command run from `directory`: the user's global file, and the project file in `directory` and in its repository's top-level directory.
    ///
    /// A file that is there but cannot be read as Cursor's rules — no JSON object, a `permissions`, `allow` or `deny` of the wrong type, a `Shell` entry that does not parse — marks the reading unreadable, which withholds every rewrite. A missing file is no rules.
    public static func load(directory: String?, environment: [String: String] = ProcessInfo.processInfo.environment) -> WrappedRunPermission {
        var files = [AgentPaths.cursorDirectory(environment: environment).appendingPathComponent("cli-config.json")]
        if let directory {
            var seen: Set<String> = []
            let directories = [directory, WrappedRunPermission.repositoryRoots(of: directory).top].compactMap(\.self).filter {
                seen.insert(URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path).inserted
            }
            files += directories.map { URL(fileURLWithPath: $0).appendingPathComponent(".cursor/cli.json") }
        }
        let readings = files.map(rules(at:))
        guard readings.allSatisfy({ $0 != nil }) else {
            return WrappedRunPermission(allowed: [], vetoed: [], hasUnreadableSettings: true)
        }
        let read = readings.compactMap(\.self)
        return WrappedRunPermission(allowed: read.flatMap(\.allowed), vetoed: read.flatMap(\.vetoed))
    }

    /// Whether a build rewritten into `legs` — each a statement as the rewrite leaves it, `swift-sure run -- ` in front — adds no prompt that the line as written would not meet under `permission`.
    ///
    /// Either an allow rule covers every wrapped statement, or no allow rule covers every statement as written, in which case Cursor would have asked about the line anyway.
    public static func addsNoNewPrompt(_ permission: WrappedRunPermission, legs: [String]) -> Bool {
        let prefix = IndexSuggestion.toolchainRunPrefix
        let written = legs.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }
        return permission.addsNoPrompt(legs: legs, mode: nil) || !permission.addsNoPrompt(legs: written, mode: nil)
    }

    /// The patterns one permission entry gives, `*` standing for any text: none for an entry that is not a `Shell` rule, and `nil` for a `Shell` entry that does not parse.
    ///
    /// A bare `Shell` or `Shell(*)` is every command. `Shell(base)` is the command alone or followed by a space and anything; `Shell(base:args)` is the command followed by a space and the argument glob, and the command alone too where the glob is a single `*`.
    static func patterns(of entry: String) -> [String]? {
        let entry = entry.trimmingCharacters(in: .whitespaces)
        guard entry == "Shell" || entry.hasPrefix("Shell(") else { return [] }
        guard entry != "Shell" else { return ["*"] }
        guard entry.hasSuffix(")") else { return nil }
        let body = String(entry.dropFirst("Shell(".count).dropLast()).trimmingCharacters(in: .whitespaces)
        guard body != "*" else { return ["*"] }
        guard let colon = body.firstIndex(of: ":") else {
            return body.isEmpty ? nil : [body, body + " *"]
        }
        let base = body[..<colon].trimmingCharacters(in: .whitespaces)
        let arguments = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !arguments.isEmpty else { return nil }
        return arguments == "*" ? [base, base + " *"] : [base + " " + arguments]
    }

    /// The allow and deny patterns of the Cursor permission file at `url`: none where there is no file, and `nil` where it is there but cannot be read as Cursor's rules.
    private static func rules(at url: URL) -> (allowed: [String], vetoed: [String])? {
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], []) }
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        guard let permissions = object["permissions"] else { return ([], []) }
        guard let permissions = permissions as? [String: Any],
              let allowed = patterns(in: permissions["allow"]),
              let vetoed = patterns(in: permissions["deny"])
        else {
            return nil
        }
        return (allowed, vetoed)
    }

    /// The patterns of every `Shell` entry in the list `list`: none where there is no list, and `nil` where it is not a list of strings or one of its `Shell` entries does not parse.
    private static func patterns(in list: Any?) -> [String]? {
        guard let list else { return [] }
        guard let entries = list as? [Any] else { return nil }
        var patterns: [String] = []
        for entry in entries {
            guard let entry = entry as? String, let parsed = Self.patterns(of: entry) else { return nil }
            patterns += parsed
        }
        return patterns
    }
}
