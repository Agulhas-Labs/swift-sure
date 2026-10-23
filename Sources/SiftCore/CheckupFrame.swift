//
// Copyright © Agulhas Labs
//

import Foundation

/// The `checkup` answer for one range: the facts git gives about the change and the checks built so far, framed by `CheckupRenderer`.
public struct CheckupFrame {
    let git: GitContext
    let range: DiffRange
    /// The engine `affected`'s walk runs on, for the tests reaching the change; `nil` leaves the count out.
    let engine: SiftEngine?
    /// The walk `checkup`'s checks already ran, so the tests reaching the change are not walked for twice.
    let walk: CheckupAffectedWalk?
    /// The range argument as the caller typed it, `nil` where none was given.
    let spelledRange: String?
    var environment = ProcessInfo.processInfo.environment

    public init(git: GitContext, range: DiffRange, engine: SiftEngine? = nil, walk: CheckupAffectedWalk? = nil, spelledRange: String? = nil) {
        self.git = git
        self.range = range
        self.engine = engine
        self.walk = walk
        self.spelledRange = spelledRange
    }

    /// The answer page starting at `offset`, `notes` placed directly under its header.
    public func answer(freshness: Freshness, notes: [String?] = [], offset: Int, outcomes: [CheckupOutcome] = []) async throws -> String {
        let changed = try changedPaths()
        let uncommitted = try uncommittedChangesAtHead()
        let atCleanHead = uncommitted == 0
        var outcomes = outcomes
        // A range ending elsewhere is other content than any run recorded; `applying` names why.
        if range.to == .workingTree || atCleanHead {
            let (findings, status) = try await testRuns(changed: changed).evaluate(reach: reach)
            outcomes.append(CheckupOutcome(check: .testRuns, status: status, findings: findings))
            outcomes.append(uncovered(changed: changed).outcome())
        }
        let renderer = CheckupRenderer(
            header: freshness.headerLine,
            range: range.described,
            changedFiles: changed.count,
            findings: outcomes.flatMap(\.findings),
            checks: CheckupChecks.unbuilt.reporting(outcomes).applying(rangeEnding: range.to, atCleanHead: atCleanHead, uncommitted: uncommitted.flatMap { $0 > 0 ? $0 : nil }),
            offset: offset
        )
        return Freshness.placing(notes, under: renderer.render())
    }

    private func changedPaths() throws -> Set<String> {
        let changes = switch range.to {
        case .workingTree: try git.dirtyFiles()
        case let .revision(revision): try git.changedFiles(from: range.from, to: revision)
        }
        return Set(changes.map(\.path))
    }

    /// The uncommitted changes in the working tree, untracked files included, where the range ends at the commit `HEAD` names; `nil` where it ends elsewhere.
    private func uncommittedChangesAtHead() throws -> Int? {
        guard case let .revision(revision) = range.to, let end = git.commitHash(revision), end == git.commitHash("HEAD") else { return nil }
        return try git.dirtyFiles().count
    }

    /// The `test runs` check over the package roots the changed paths sit in.
    private func testRuns(changed: Set<String>) -> CheckupTestRuns {
        let root = git.repoRoot
        let roots = Set(changed.map { Self.packageRoot(of: $0, under: root) }).sorted()
        return CheckupTestRuns(
            ledger: RunLedger.inRepository(at: root),
            tree: TreeKey.of(repositoryRoot: root),
            toolchain: ToolchainIdentity.current(),
            packageRoots: roots,
            swiftPMRoots: Set(roots.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("Package.swift").path) }),
            checkout: root.path,
            environment: environment
        )
    }

    /// The `uncovered` check over the recorded coverage and this range's change, suggesting the newest unnarrowed test command recorded from the one package root the change sits in, else `swift test`.
    private func uncovered(changed: Set<String>) -> CheckupUncoveredCheck {
        let ledger = RunLedger.inRepository(at: git.repoRoot)
        let roots = Set(changed.map { Self.packageRoot(of: $0, under: git.repoRoot) }).sorted()
        let recorded = (ledger.records() + ledger.failedRuns.records())
            .filter { ($0.workingDirectory ?? ".") == (roots.first ?? ".") && RunNarrowing.isUnnarrowed($0.arguments) }
            .max { $0.finishedAt < $1.finishedAt }
        return CheckupUncoveredCheck(
            record: CoverageRecord.read(in: git.repoRoot),
            tree: TreeKey.of(repositoryRoot: git.repoRoot),
            changed: try? ChangedCode.inWorkingTree(against: range.from, git: git),
            base: range.fromLabel,
            testCommand: recorded?.arguments?.map(TestRunRequest.shellQuoted).joined(separator: " ") ?? "swift test",
            range: spelledRange,
            packageRoots: roots
        )
    }

    /// The tests `affected` finds reaching this range's change, and the runners it names.
    private func reach() async throws -> (tests: Int, runners: AffectedRunners)? {
        let output: AffectedRenderer.Output
        if let walk {
            output = try await walk.output()
        } else if let engine {
            output = try await engine.affectedOutput(options: AffectedOptions(range: range.affectedRange))
        } else {
            return nil
        }
        return (output.testCount, output.runners)
    }

    /// The nearest directory at or above `path`'s holding a `Package.swift`, repository-relative; the root where none does.
    static func packageRoot(of path: String, under root: URL) -> String {
        var components = path.split(separator: "/").dropLast().map(String.init)
        while !components.isEmpty {
            let directory = components.joined(separator: "/")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(directory).appendingPathComponent("Package.swift").path) {
                return directory
            }
            components.removeLast()
        }
        return "."
    }
}
