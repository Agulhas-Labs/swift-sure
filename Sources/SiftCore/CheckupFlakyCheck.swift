//
// Copyright © Agulhas Labs
//

/// The `flaky` check: a reached test the run log records both failing and passing on identical bytes.
struct CheckupFlakyCheck {
    /// The outcome over `reached`, the whole reached set with suites and targets expanded, given the run log's same-tree reading; `nil` evidence is a log with no run that recorded a tree and a command line.
    static func outcome(evidence: CheckupFlakeEvidence?, reached: [TestSymbol]) -> CheckupOutcome {
        guard let evidence, evidence.runs > 0 else {
            return CheckupOutcome(check: .flakyTests, status: .notChecked(reason: "no recorded run with a tree and a command line"), findings: [])
        }
        guard !reached.isEmpty else {
            return CheckupOutcome(check: .flakyTests, status: .notChecked(reason: "no reached test"), findings: [])
        }
        let findings = reached.sorted().compactMap { test -> CheckupFinding? in
            let matched = evidence.tests.filter { names(test, $0.name) }
            guard let first = matched.first else { return nil }
            let failed = matched.reduce(0) { $0 + $1.failed }
            let runs = matched.reduce(0) { $0 + $1.runs }
            return CheckupFinding(
                findingClass: .flaky,
                path: nil,
                line: nil,
                endLine: nil,
                text: "\(test.described) failed and passed on identical bytes, failing \(failed) of \(runs) runs",
                command: "\(ProductName.current.binary) flakes \(TestRunRequest.shellQuoted(first.name))"
            )
        }
        return CheckupOutcome(check: .flakyTests, status: .checked(basis: "over \(evidence.runs) run\(evidence.runs == 1 ? "" : "s")", bound: nil), findings: findings)
    }

    /// Whether `recorded`, a name as a run logged it, names `test` whole, with `.` and `/` read as one separator.
    static func names(_ test: TestSymbol, _ recorded: String) -> Bool {
        let logged: [String] = if let xctest = TestIdentifier.xctestLogName(recorded) {
            ["\(xctest.qualifiedType).\(xctest.method)", "\(xctest.qualifiedType.split(separator: ".").dropFirst().joined(separator: ".")).\(xctest.method)"]
        } else {
            [recorded]
        }
        let dotted = [test.target, test.suite].compactMap(\.self).joined(separator: ".") + (test.function.map { "." + $0 } ?? "")
        let spellings = Set([test.described, dotted].map(separated))
        return logged.map(separated).contains { name in
            !name.isEmpty && name.first != "." && spellings.contains { $0 == name || $0.hasSuffix("." + name) }
        }
    }

    private static func separated(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: ".")
    }
}
