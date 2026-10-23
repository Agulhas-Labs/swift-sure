//
// Copyright © Agulhas Labs
//

import Foundation

/// The `uncovered` check: the `changed lines:` line `diff --coverage` computes, read from the recorded coverage where that record answers for this change and this time.
///
/// It reads what `run --coverage` recorded and runs nothing. A record is used only where its tree key is the working tree's, it is no older than ``RunLedger/trustWindow``, and every changed Swift file is in its measured or unmeasured set.
struct CheckupUncoveredCheck {
    /// The repository's recorded coverage, `nil` where none was recorded.
    let record: CoverageRecord?
    /// The working tree's content key, `nil` where git would not key it.
    let tree: TreeKey?
    /// The range's change against its before side, `nil` where git could not list it.
    let changed: ChangedCode?
    /// The before side as `diff` names it.
    let base: String
    /// The unnarrowed test command to suggest, as its words.
    let testCommand: String
    /// The range as the caller spelled it, `nil` where none was given.
    var range: String?
    /// The repository-relative package roots the changed paths sit in, `"."` for the repository's own.
    var packageRoots: [String] = ["."]
    var now = Date()

    /// The finding, if a changed executable line did not run, and the status the check reports.
    func outcome() -> CheckupOutcome {
        guard let record else { return notChecked("none recorded in this checkout") }
        guard let tree else { return unchecked("a tree git will not key (git would not hash this working tree)") }
        guard let changed else { return unchecked("git could not list the change") }
        let covered = Set(record.measured.keys).union(record.unmeasured)
        guard record.tree == tree.value, Set(changed.paths).isSubset(of: covered) else {
            return notChecked("recorded for another change set")
        }
        guard let measuredAt = record.measuredAt else { return notChecked("recorded at a time it cannot tell, past the trust window") }
        let age = now.timeIntervalSince(measuredAt)
        guard age <= RunLedger.trustWindow else {
            return notChecked("recorded \(ProvedRunAnswer.elapsed(max(0, age))) ago, past the trust window")
        }
        let unmeasured = Set(changed.paths).intersection(record.unmeasured).count
        let basis = unmeasured == 0 ? nil : "\(unmeasured) \(unmeasured == 1 ? "file" : "files") unmeasured"
        let status = CheckupStatus.checked(basis: basis, bound: nil)
        guard let line = CoverageChangedLines.line(changed: changed.lines, counts: record.measured), line.contains("; uncovered: ") else {
            return CheckupOutcome(check: .coverage, status: status, findings: [])
        }
        let omitted = line.range(of: #", \+\d+ more$"#, options: .regularExpression) != nil
        let finding = CheckupFinding(
            findingClass: .uncovered,
            path: nil,
            line: nil,
            endLine: nil,
            text: line,
            command: omitted ? pointer : ""
        )
        return CheckupOutcome(check: .coverage, status: status, findings: [finding])
    }

    /// The `diff --coverage` that shows the change's coverage by declaration; none where the checkup was given a range, since `diff --coverage` takes no range and pairs the working tree against `HEAD`.
    private var pointer: String {
        guard range?.isEmpty ?? true else { return "" }
        return "\(ProductName.current.binary) diff --coverage"
    }

    private func unchecked(_ reason: String) -> CheckupOutcome {
        CheckupOutcome(check: .coverage, status: .notChecked(reason: reason), findings: [])
    }

    /// `reason` with the coverage run that would answer it; the reason alone where the change spans several package roots, since one coverage run records one package.
    private func notChecked(_ reason: String) -> CheckupOutcome {
        guard packageRoots.count <= 1 else { return unchecked(reason) }
        let root = packageRoots.first ?? "."
        let location = root == "." ? "" : "--root \(TestRunRequest.shellQuoted(root)) "
        return unchecked("\(reason) — \(ProductName.current.binary) run \(location)--coverage --from \(base) -- \(testCommand)")
    }
}
