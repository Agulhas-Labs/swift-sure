//
// Copyright © Agulhas Labs
//

import Foundation

extension ShardAnswerRenderer {
    /// One plan of a multi-plan run: its name, its plan of shards and what that reconciled to.
    struct PlanAnswer {
        let name: String
        let plan: ShardPlan
        let reconciliation: ShardReconciliation
    }

    /// The answer to a run over several plans, in one piece: the verdict, a line per plan with its own failure detail under it, the run's totals, every shard, the slowest tests across all plans, then the run's timing, re-run command, devices and housekeeping — each once.
    ///
    /// `declared` is every plan the run was asked for, in order; one that enumerated no tests has a line of its own saying so, with no entry in `answers`.
    func render(plans answers: [PlanAnswer], declared: [String], shards: Int) -> String {
        let counts = Self.total(answers.map(\.reconciliation.counts))
        let failing = answers.filter { !$0.reconciliation.isGreen }
        let withheld = answers.contains { $0.reconciliation.counts.missing > 0 }
        var sections: [[String]] = [[verdict(failing: failing, passed: counts.passed, plans: declared.count, shards: shards)] + planLines(answers, declared: declared)]
        sections[0].append("  total: \(counts.line)")
        if withheld, !crashReports.isEmpty {
            sections.append(["crash reports written during the run:"] + crashReports.map { "  \($0)" })
        }
        sections.append(answers.flatMap { answer in answer.reconciliation.shards.flatMap { shardLines($0, plan: answer.name) } } + (phases.map { [$0.line] } ?? []))
        sections.append(slowest(answers))
        sections.append(Self.distinct(answers.flatMap { notesSection($0.reconciliation, plan: $0.plan) }))
        sections.append(rerun(failing))
        sections.append(sweepLines + (devicesLine.map { [$0] } ?? []) + (derivedDataLine.map { [$0] } ?? []))
        return sections.filter { !$0.isEmpty }.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private func verdict(failing: [PlanAnswer], passed: Int, plans: Int, shards: Int) -> String {
        guard !failing.isEmpty else {
            return "✔ \(ProductName.current.binary) test — \(passed) tests passed across \(pluralized(plans, "plan")) on \(pluralized(shards, "shard"))"
        }
        let reasons = failing.map { "\($0.name): \(worstReasons($0.reconciliation).joined(separator: " · "))" }.joined(separator: "; ")
        let exit = failing.map(\.reconciliation.exitCode).first { $0 != 0 }.map { " — exit \($0)" } ?? ""
        return "✘ \(ProductName.current.binary) test — \(reasons)\(exit)"
    }

    /// A line per plan in the order asked for, a plan's failure detail indented beneath it.
    private func planLines(_ answers: [PlanAnswer], declared: [String]) -> [String] {
        declared.flatMap { name -> [String] in
            guard let answer = answers.first(where: { $0.name == name }) else {
                return ["  \(name): no tests enumerated"]
            }
            let reconciliation = answer.reconciliation
            let detail = failureSection(reconciliation)
                + (missingSection(reconciliation, crashReportsIncluded: false) ?? [])
                + unlistedSection(reconciliation, plan: answer.plan)
                + undecidedSection(reconciliation)
                + reconciliation.duplicated.map(duplicationLine)
            return ["  \(name): \(reconciliation.counts.line)"] + detail.map { "    \($0)" }
        }
    }

    /// The five slowest tests across every plan, a test's row naming its plan only where the same test ran in two or more.
    private func slowest(_ answers: [PlanAnswer]) -> [String] {
        let rows = answers.flatMap { answer in answer.reconciliation.timings.map { (plan: answer.name, timing: $0) } }
        let sharedTests = Dictionary(grouping: rows, by: \.timing.test.enumerated).filter { $0.value.count > 1 }.keys
        let top = rows.sorted { left, right in
            left.timing.seconds == right.timing.seconds
                ? left.timing.test.enumerated < right.timing.test.enumerated
                : left.timing.seconds > right.timing.seconds
        }.prefix(5)
        guard !top.isEmpty else {
            return []
        }
        return ["slowest:"] + top.map { row in
            let name = row.timing.test.enumerated
            return "  \(ShardSeconds.text(row.timing.seconds))  \(sharedTests.contains(name) ? "\(row.plan): " : "")\(name)"
        }
    }

    /// One command that re-runs the failing plans' failed tests alone: the caller's prefix names only those plans.
    private func rerun(_ failing: [PlanAnswer]) -> [String] {
        var seen = Set<String>()
        let failed = failing.flatMap(\.reconciliation.failed).filter { seen.insert($0.enumerated).inserted }
        guard !failed.isEmpty else {
            return []
        }
        let args = failed.map { TestRunRequest.shellQuoted($0.enumerated) }.joined(separator: " --only ")
        guard let rerunCommand else {
            return ["re-run just these with --shards 1:", "  --only \(args)"] + stockHint
        }
        return ["re-run just these, serially:", "  \(rerunCommand) --shards 1 --only \(args)\(rerunSuffix ?? "")"] + stockHint
    }

    private static func total(_ counts: [ReconciliationCounts]) -> ReconciliationCounts {
        ReconciliationCounts(
            expected: counts.map(\.expected).reduce(0, +),
            ran: counts.map(\.ran).reduce(0, +),
            passed: counts.map(\.passed).reduce(0, +),
            failed: counts.map(\.failed).reduce(0, +),
            skipped: counts.map(\.skipped).reduce(0, +),
            missing: counts.map(\.missing).reduce(0, +),
            duplicated: counts.map(\.duplicated).reduce(0, +),
            linesLost: counts.map(\.linesLost).reduce(0, +)
        )
    }

    private static func distinct(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }
}
