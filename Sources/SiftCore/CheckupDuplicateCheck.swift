//
// Copyright © Agulhas Labs
//

/// The `duplicate` check: a declaration the change added, or whose body it changed, that clears both of `dupes`' gates against another declaration.
struct CheckupDuplicateCheck {
    /// Why the check did not run.
    static var noSeedReason: String {
        "no added or body-changed declaration"
    }

    /// Whether `files` hold any declaration that can seed: one added, or a leaf whose own text changed.
    static func hasSeeds(in files: [FileDiff]) -> Bool {
        files.contains { file in file.changes.contains(where: isSeed) }
    }

    /// The fingerprints lying inside an added or body-changed declaration of `files`, which is every member of a wholly added type as well.
    static func seeds(in files: [FileDiff], fingerprints: [DeclarationFingerprint]) -> Set<DupesSeedKey> {
        let ranges = Dictionary(grouping: files, by: \.path).mapValues { group in
            group.flatMap(\.changes).filter(isSeed).compactMap(\.newRange)
        }
        return Set(fingerprints.compactMap { fingerprint -> DupesSeedKey? in
            let declaration = fingerprint.declaration
            guard ranges[declaration.path]?.contains(where: { $0.line <= declaration.line && declaration.endLine <= $0.endLine }) == true else { return nil }
            return DupesSeedKey(fingerprint)
        })
    }

    /// The outcome of `dupes`' comparison with `seeds` proposing, one finding per group, closest pair first; groups past the cap are counted on the bound.
    static func outcome(answer: DupesAnswer, seeds: Set<DupesSeedKey>) -> CheckupOutcome {
        let findings = answer.groups.map { finding(for: $0, seeds: seeds) }
        let pastCap = answer.totalGroups - answer.groups.count
        return CheckupOutcome(
            check: .duplicates,
            status: .checked(basis: nil, bound: pastCap > 0 ? "\(pastCap) more past the cap" : nil),
            findings: findings
        )
    }

    /// The outcome for a range that changed nothing able to seed.
    static var unseeded: CheckupOutcome {
        CheckupOutcome(check: .duplicates, status: .notChecked(reason: noSeedReason), findings: [])
    }

    private static func isSeed(_ change: DeclarationChange) -> Bool {
        switch change.kind {
        case .added: true
        case .changed: change.textChanged
        case .removed, .moved: false
        }
    }

    private static func finding(for group: DupesAnswer.Group, seeds: Set<DupesSeedKey>) -> CheckupFinding {
        let (first, second) = group.closest
        let secondIsSeed = !seeds.contains(DupesSeedKey(first)) && seeds.contains(DupesSeedKey(second))
        let located = (secondIsSeed ? second : first).declaration
        let partner = (secondIsSeed ? first : second).declaration
        let name = located.qualifiedName.prefix { $0 != "(" }
        return CheckupFinding(
            findingClass: .duplicate,
            path: located.path,
            line: located.line,
            endLine: located.endLine,
            text: "\(located.qualifiedName) and \(partner.qualifiedName) at \(partner.path):\(partner.line)-\(partner.endLine) clear both gates (\(overlap(group.bestOverlap)))",
            command: "\(ProductName.current.binary) similar \(TestRunRequest.shellQuoted(String(name)))"
        )
    }

    private static func overlap(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        return "\(hundredths / 100).\(hundredths % 100 < 10 ? "0" : "")\(hundredths % 100)"
    }
}
