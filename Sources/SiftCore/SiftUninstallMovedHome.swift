//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

extension SiftUninstall {
    /// What a home holds where this tool wrote it: an entry of one kind, and for a directory whose entries its writers name, which entries those are.
    enum HomeEntry: Equatable {
        case file
        case directory
        /// A directory holding only what ``HomeEntry/admits(_:kind:)`` accepts.
        case directoryOf(Inner)

        /// Whether `kind` is the kind this entry is written as.
        func matches(_ kind: PathKind) -> Bool {
            switch self {
            case .file:
                kind == .file
            case .directory, .directoryOf:
                kind == .directory
            }
        }

        /// Whether `name`, of `kind`, is an entry this tool's writers put in the directory `self` describes; `true` for a directory not checked one level in.
        func admits(_ name: String, kind: PathKind) -> Bool {
            guard case let .directoryOf(inner) = self else { return true }
            return switch inner {
            case .advice:
                Self.adviceEntries[name]?.matches(kind) ?? (kind == .file && Self.isSessionFile(name))
            case .callers:
                // CallAttribution's slips and their claimed copies, `<session>.<stamp>-<id>.json` and `claimed-<uuid>-<slip>`.
                kind == .file && name.hasSuffix(".json")
            case .replay:
                // `audit`'s scratch, a directory per run named by a fresh UUID, which an interrupted run can leave.
                kind == .directory && UUID(uuidString: name) != nil
            }
        }

        /// What `AdviceLedger` and the logs beside it write in the advice directory, by name, other than a session's state.
        static let adviceEntries: [String: HomeEntry] = [
            ".lock": .file, // AdviceLedger's lock
            "suppressions.jsonl": .file, // SuppressionLog
            "answered.jsonl": .file, // AnsweredLog
            "answers": .directory, // AnsweredLog's markers
            "reuse": .directory, // ReuseNudgeMarks
            "backoff": .directory, // InPlaceBackoff
            "cursor-rewrites": .directory, // CursorRewriteNotices
        ]

        /// Whether `name` is a session's state as `AdviceLedger` names it: the session id cut to letters, digits, `-` and `_`, then `.json`.
        static func isSessionFile(_ name: String) -> Bool {
            guard name.hasSuffix(".json") else { return false }
            let stem = name.dropLast(".json".count)
            return !stem.isEmpty && stem.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

extension SiftUninstall.HomeEntry {
    /// The directories whose entries are checked one level in, each named for its writer.
    enum Inner: Equatable {
        case advice
        case callers
        case replay
    }
}

extension SiftUninstall {
    /// Every top-level entry this tool writes in its home, with its kind, each beside its writer; anything else in a moved home stops the purge.
    static let homeEntries: [String: HomeEntry] = [
        "deploys.jsonl": .file, // DeployLog, and `install.sh`'s `record_deploy`
        "usage.jsonl": .file, // UsageLog
        "run.jsonl": .file, // RunUsageLog
        "server.jsonl": .file, // ServerLifecycleLog
        "advice": .directoryOf(.advice), // AdviceLedger: suppressions, answers, backoff, reuse, rewrites and its lock sit inside
        "callers": .directoryOf(.callers), // SiftPaths.callers, for CallAttribution
        "replay": .directoryOf(.replay), // AuditCommand's scratch, beside the advice directory
        "transcript-tallies.json": .file, // TranscriptTallyCache
        "roots.json": .file, // RootsRegistry
        "redaction-salt": .file, // Redactor
        "report.html": .file, // ReportCommand
        "lookups-declined": .file, // LookupsDeclineRecord
        "libraries": .directory, // AnimationsOffLibrary
        "statusline": .directory, // the status line an earlier release wrote
    ]

    /// Every entry in `home` this tool did not write, sorted, one inside a checked directory spelled `advice/<name>`: a name it does not write, one of the wrong kind, or a checked directory that could not be listed.
    static func foreignEntries(in home: URL) -> [String]? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: home.path) else { return nil }
        var foreign: [String] = []
        for name in entries.sorted() {
            let url = home.appendingPathComponent(name)
            guard let entry = homeEntries[name], entry.matches(PathKind.of(url)) else {
                foreign.append(name)
                continue
            }
            guard case .directoryOf = entry else { continue }
            guard let inside = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                foreign.append(name)
                continue
            }
            foreign += inside.sorted().filter { !entry.admits($0, kind: PathKind.of(url.appendingPathComponent($0))) }.map { "\(name)/\($0)" }
        }
        return foreign
    }

    /// Why a home `variable` moved is not deleted whole: the first entry in it this tool did not write and how many more, or `nil` when it holds only ``homeEntries``.
    static func foreignEntriesRefusal(in home: URL, namedBy variable: String) -> String? {
        guard let foreign = foreignEntries(in: home) else {
            return "the directory \(variable) names, which could not be listed — remove it by hand"
        }
        guard let first = foreign.first else { return nil }
        let binary = SiftPaths.binaryName
        let more = foreign.count - 1
        let what = more == 0 ? "\(first), which \(binary) did not write" : "\(first) and \(more) more \(more == 1 ? "entry" : "entries") \(binary) did not write"
        return "the directory \(variable) names, holding \(what) — remove it by hand"
    }

    /// Why the home a variable moved is not deleted now, read again just before the delete: what the listing found may have changed while the uninstall's other steps ran.
    static func movedHomeRefusal(_ home: URL, namedBy variable: String) -> String? {
        PathKind.of(home).refusal ?? foreignEntriesRefusal(in: home, namedBy: variable)
    }
}
