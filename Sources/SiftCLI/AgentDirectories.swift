//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Where `--cursor-dir` and `--codex-dir` send Cursor's and Codex's files, each `nil` when its flag was not given.
struct AgentDirectories: Equatable {
    var cursor: String?
    var codex: String?

    /// `target` of `agent` at the directory its flag names, or as detection has it when the agent has no flag.
    func moved(_ target: AgentDetection.Target, of agent: Agent, environment: [String: String]) -> (path: String, what: String) {
        let flag: String?
        var what = target.what
        switch agent {
        case .claude:
            flag = nil
        case .cursor:
            flag = cursor
        case .codex:
            flag = codex
            if codex != nil {
                what = what.replacingOccurrences(of: AgentPaths.codexHome(flag: nil, environment: environment).source, with: "--codex-dir")
            }
        }
        guard let flag else { return (target.url.path, what) }
        return (URL(fileURLWithPath: flag, isDirectory: true).appendingPathComponent(target.url.lastPathComponent).path, what)
    }

    /// What detection prints, with each file at the directory its flag names, the way the dry run lists it.
    func text(_ detection: AgentDetection, environment: [String: String]) -> String {
        detection.findings.flatMap { finding in
            [finding.line] + finding.targets.map { target in
                let placed = moved(target, of: finding.agent, environment: environment)
                return "    would write \(placed.path) (\(placed.what))"
            }
        }
        .joined(separator: "\n")
    }

    /// One note for each directory flag given whose agent is not among `picks`, so the flag is never silently ignored.
    func ignoredNotes(picks: [AgentSelection.Pick]) -> [String] {
        [(cursor, Agent.cursor, "--cursor-dir", "Cursor"), (codex, Agent.codex, "--codex-dir", "Codex")].compactMap { directory, agent, flag, name in
            guard directory != nil, !picks.contains(where: { $0.agent == agent }) else { return nil }
            return "note: \(flag) applies only to \(name)'s install, and \(name) is not being installed, so it was ignored"
        }
    }
}
