//
// Copyright © Agulhas Labs
//

import Foundation

/// The `test runs` check: the `failed` and `unproved` findings the run ledger holds for this content, and the status the check reports.
///
/// It reads what `run` recorded and runs nothing. A green proves a package root only where `--proved`'s own ``RunLedger/trust(tree:command:toolchain:workingDirectory:now:environment:)`` accepts it from that root, and its refusals are worded as `--proved` words them.
struct CheckupTestRuns {
    let ledger: RunLedger
    /// The working tree's content key, `nil` where git would not key it.
    let tree: TreeKey?
    /// The toolchain asking, `nil` where none would name itself.
    let toolchain: ToolchainIdentity?
    /// The repository-relative package roots the change touches, `"."` for the root, in order.
    let packageRoots: [String]
    /// The package roots holding a `Package.swift`.
    let swiftPMRoots: Set<String>
    /// This checkout's path, so a log written here is named relative to it.
    let checkout: String
    var now = Date()
    var environment: [String: String] = ProcessInfo.processInfo.environment

    /// The not-counting greens an `unproved` line names before it counts the rest.
    static var namedGreens: Int {
        3
    }

    /// The findings and the check's status; `reach` is asked, once, only where a line needs the tests `affected` finds reaching the change.
    func evaluate(reach: () async throws -> (tests: Int, runners: AffectedRunners)?) async throws -> (findings: [CheckupFinding], status: CheckupStatus) {
        guard RunLedger.isOn(environment: environment) else {
            return ([], .notChecked(reason: "the run ledger switched off (\(RunLedger.switchName)=0)"))
        }
        guard let tree else {
            return ([], .notChecked(reason: "a tree git will not key (git would not hash this working tree)"))
        }
        guard let toolchain else {
            return ([], .notChecked(reason: "no Swift toolchain on PATH would name itself"))
        }
        let reds = ledger.failedRuns.records().filter { $0.tree == tree.value && now.timeIntervalSince($0.finishedAt) <= RunLedger.trustWindow }
        let greens = ledger.records().filter { $0.tree == tree.value }
        guard !reds.isEmpty || !greens.isEmpty else {
            return ([], .notChecked(reason: "no run recorded on this content"))
        }
        let proving = ledger.provingRecords().filter { $0.tree == tree.value }
        let open = reds.filter { red in !proving.contains { clears($0, red) } }
        var findings: [CheckupFinding] = []
        var excused: [String] = []
        for red in open {
            if let reason = Self.notAFailure(red) {
                excused.append("\(red.command): \(reason), \(age(of: red)) ago")
            } else {
                findings.append(failed(red))
            }
        }
        var proofs: [String] = []
        var unproved: [String] = []
        for root in packageRoots {
            if let proof = proof(from: root, tree: tree, toolchain: toolchain, greens: greens) {
                proofs.append("\(proof.command) proved green on this content \(age(of: proof)) ago\(Self.from(root))")
            } else {
                unproved.append(root)
            }
        }
        if !unproved.isEmpty {
            let reached = try await reach()
            findings += unproved.map { unprovedFinding(root: $0, tree: tree, toolchain: toolchain, greens: greens, reached: reached) }
        }
        let basis = ((proofs.isEmpty || !unproved.isEmpty ? ["recorded"] : proofs) + excused).joined(separator: "; ")
        return (findings, .checked(basis: basis, bound: nil))
    }

    /// Why `red` is not a failure of the code, or `nil` where it is one.
    static func notAFailure(_ red: RunLedger.Record) -> String? {
        if red.stoppedBySift == true {
            return "stopped by \(ProductName.current.binary)"
        }
        return switch red.exitCode {
        case 0: "exit 0 refused as a proof"
        case 4: "exit 4, no test matched"
        case 6: "exit 6, an unclean inventory under --require-inventory"
        default: nil
        }
    }
}

private extension CheckupTestRuns {
    /// Whether `green` clears `red`: after it, on the same content, directory and toolchain, of the same command or an unnarrowed one.
    func clears(_ green: RunLedger.Record, _ red: RunLedger.Record) -> Bool {
        green.finishedAt > red.finishedAt && green.toolchain == red.toolchain
            && (green.workingDirectory ?? ".") == (red.workingDirectory ?? ".")
            && (green.command == red.command || RunNarrowing.isUnnarrowed(green.arguments))
    }

    func failed(_ red: RunLedger.Record) -> CheckupFinding {
        let exit = red.exitCode.map { "exit \($0)" } ?? "exit not recorded"
        let log = red.log.map { name in
            let directory = red.checkout == nil || red.checkout == checkout ? "" : (red.checkout ?? "") + "/"
            return "log \(directory)\(SiftPaths.cache(in: URL(fileURLWithPath: red.checkout ?? checkout)).lastPathComponent)/runs/\(name)"
        } ?? red.shardedRun(directory: red.logsDirectory(readFrom: checkout)) ?? "no transcript kept"
        let text = "\(red.command)\(Self.from(red.workingDirectory ?? ".")) failed \(age(of: red)) ago (\(exit); \(log))"
        return CheckupFinding(findingClass: .failed, path: nil, line: nil, endLine: nil, text: text, command: Self.rerun(red.arguments, else: red.command, from: red.workingDirectory ?? "."))
    }

    /// The green `--proved` trusts for an unnarrowed command from `root`, if any.
    func proof(from root: String, tree: TreeKey, toolchain: ToolchainIdentity, greens: [RunLedger.Record]) -> RunLedger.Record? {
        for command in unnarrowedCommands(greens) {
            if case let .proved(record) = ledger.trust(tree: tree, command: command, toolchain: toolchain, workingDirectory: root, now: now, environment: environment) {
                return record
            }
        }
        return nil
    }

    /// The commands of the unnarrowed greens on this content, newest first, each once.
    func unnarrowedCommands(_ greens: [RunLedger.Record]) -> [String] {
        var seen: Set<String> = []
        return greens.filter { RunNarrowing.isUnnarrowed($0.arguments) && seen.insert($0.command).inserted }.map(\.command)
    }

    func unprovedFinding(root: String, tree: TreeKey, toolchain: ToolchainIdentity, greens: [RunLedger.Record], reached: (tests: Int, runners: AffectedRunners)?) -> CheckupFinding {
        var notCounting = unnarrowedCommands(greens).compactMap { command -> String? in
            guard case let .notProved(reason) = ledger.trust(tree: tree, command: command, toolchain: toolchain, workingDirectory: root, now: now, environment: environment) else { return nil }
            return "\(command): \(ProvedRunAnswer.explain(reason, command: command))"
        }
        notCounting += greens.filter { !RunNarrowing.isUnnarrowed($0.arguments) }.map { "\(Self.narrowedName(of: $0)), narrowed, \(age(of: $0)) ago" }
        let named = notCounting.prefix(Self.namedGreens).joined(separator: "; ")
        let more = notCounting.count > Self.namedGreens ? "; +\(notCounting.count - Self.namedGreens) more" : ""
        let greensClause = notCounting.isEmpty ? "" : " (not counting: \(named)\(more))"
        let reachClause = reached.map { "; \($0.tests) \($0.tests == 1 ? "test reaches" : "tests reach") the change" } ?? ""
        let text = "no unnarrowed test run is proved green on this content\(Self.from(root))\(greensClause)\(reachClause)"
        return CheckupFinding(findingClass: .unproved, path: nil, line: nil, endLine: nil, text: text, command: suggestion(root: root, runners: reached?.runners ?? .both))
    }

    /// The newest unnarrowed test command recorded from `root`, else `swift test` in a SwiftPM package, else the runner `affected` names.
    func suggestion(root: String, runners: AffectedRunners) -> String {
        let recorded = (ledger.records() + ledger.failedRuns.records())
            .filter { ($0.workingDirectory ?? ".") == root && RunNarrowing.isUnnarrowed($0.arguments) }
            .max { $0.finishedAt < $1.finishedAt }
        if let arguments = recorded?.arguments {
            return Self.rerun(arguments, else: "", from: root)
        }
        let fallback = swiftPMRoots.contains(root) || !runners.xcodebuild ? "swift test" : "xcodebuild test"
        return Self.rerun(fallback.split(separator: " ").map(String.init), else: "", from: root)
    }

    /// The command of a narrowed record, its narrowing flags counted rather than listed.
    static func narrowedName(of record: RunLedger.Record) -> String {
        record.arguments.flatMap(RunNarrowing.summary) ?? record.command
    }

    func age(of record: RunLedger.Record) -> String {
        ProvedRunAnswer.elapsed(max(0, now.timeIntervalSince(record.finishedAt)))
    }

    /// ` from <dir>` for a package root other than the repository's.
    static func from(_ root: String) -> String {
        root == "." ? "" : " from \(root)"
    }

    /// `swift-sure run -- <argv>`, shell-quoted, with `--root <dir>` before the `--` for a package root other than the repository's, so it runs there from the repository root; `command` as recorded where no argv was kept.
    static func rerun(_ arguments: [String]?, else command: String, from root: String) -> String {
        let location = root == "." ? "" : "--root \(TestRunRequest.shellQuoted(root)) "
        return "\(ProductName.current.binary) run \(location)-- " + (arguments.map { $0.map(TestRunRequest.shellQuoted).joined(separator: " ") } ?? command)
    }
}
