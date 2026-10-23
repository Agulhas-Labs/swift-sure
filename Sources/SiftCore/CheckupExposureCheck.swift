//
// Copyright © Agulhas Labs
//

/// The `exposure` check: `diff`'s access section, quoted where it counts a declaration with no use outside its module or used only inside its package.
struct CheckupExposureCheck {
    let gatherer: DiffGatherer
    /// The `diff` command each finding points to: over the range the checkup was given, bare where none was.
    let diffCommand: String

    /// The verdict line as `diff` prints it and the published-library question lines, each a finding of its own; the per-declaration lines stay in `diff`.
    func outcome(files: [FileDiff], semantic: SemanticInput) async throws -> CheckupOutcome {
        guard let report = try await gatherer.accessReport(files: files, semantic: semantic) else {
            return CheckupOutcome(check: .exposure, status: .checked(basis: nil, bound: nil), findings: [])
        }
        let findings = report.findings
        let status = CheckupStatus.checked(basis: Self.basis(findings), bound: Self.bound(report))
        guard findings.contains(where: { $0.verdict != AccessFinding.Verdict.needsLevel }), let verdict = AccessSection.verdictLine(findings) else {
            return CheckupOutcome(check: .exposure, status: status, findings: [])
        }
        let lines = [verdict] + AccessSection.publishedLines(findings).map { $0.trimmingCharacters(in: .whitespaces) }
        return CheckupOutcome(check: .exposure, status: status, findings: lines.map {
            CheckupFinding(findingClass: .exposed, path: nil, line: nil, endLine: nil, text: $0, command: diffCommand)
        })
    }

    /// `store-resolved` where the store resolved every subject, else `name-matched`; bare where nothing was judged.
    static func basis(_ findings: [AccessFinding]) -> String? {
        guard !findings.isEmpty else { return nil }
        return findings.allSatisfy { $0.nameMatchedOn == nil } ? "store-resolved" : "name-matched"
    }

    /// What the lookup budget left out, counted.
    static func bound(_ report: AccessReport) -> String? {
        guard report.notChecked > 0 else { return nil }
        return "\(report.findings.count) of \(report.findings.count + report.notChecked) declarations; \(report.notChecked) not looked up"
    }
}
