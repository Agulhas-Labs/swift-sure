//
// Copyright © Agulhas Labs
//

/// The status of every check, so that an answer can name each exactly once.
struct CheckupChecks: Sendable, Equatable {
    /// The reason every check carries until its own unit lands.
    static var notBuiltYet: String {
        "not built yet"
    }

    private(set) var statuses: [CheckupCheck: CheckupStatus]

    init(_ statuses: [CheckupCheck: CheckupStatus]) {
        self.statuses = statuses
    }

    /// Every check on `not checked:`, for the checks that are not built yet.
    static var unbuilt: CheckupChecks {
        CheckupChecks(Dictionary(uniqueKeysWithValues: CheckupCheck.allCases.map { ($0, .notChecked(reason: notBuiltYet)) }))
    }

    /// These statuses with each of `outcomes`' checks set to its own.
    func reporting(_ outcomes: [CheckupOutcome]) -> CheckupChecks {
        CheckupChecks(statuses.merging(outcomes.map { ($0.check, $0.status) }) { $1 })
    }

    /// A check nobody reported is not checked: it never silently reads as clean.
    func status(of check: CheckupCheck) -> CheckupStatus {
        statuses[check] ?? .notChecked(reason: "no status reported")
    }

    /// These statuses for a range ending at `end`.
    ///
    /// A run records the working tree's content, so a range ending at another revision puts the checks that read recorded runs on `not checked:`, unless that revision is the commit `HEAD` names and the tree is clean; the checks that read the working tree then say so beside their name.
    ///
    /// `uncommitted` is the count of changes a range ending at the commit `HEAD` names has on a dirty tree, which is then what the reason names; `nil` for a range ending at any other revision.
    func applying(rangeEnding end: DiffRange.End, atCleanHead: Bool, uncommitted: Int? = nil) -> CheckupChecks {
        guard case let .revision(revision) = end, !atCleanHead else { return self }
        let recordedReason = uncommitted.map { "\($0) uncommitted \($0 == 1 ? "change" : "changes"); a run records the working tree's content" }
            ?? "a run records the working tree's content, and this range ends at \(revision)"
        var applied = statuses
        for check in CheckupCheck.allCases {
            if check.readsRecordedRuns {
                applied[check] = .notChecked(reason: recordedReason)
            } else if check.readsWorkingTree, case let .checked(basis, bound) = status(of: check) {
                let marked = ["read against the working tree, not \(revision)", basis].compactMap(\.self).joined(separator: "; ")
                applied[check] = .checked(basis: marked, bound: bound)
            }
        }
        return CheckupChecks(applied)
    }

    /// The `checked:` and `not checked:` lists on one line, in check order.
    var rendered: String {
        let checked = CheckupCheck.allCases.compactMap { check -> String? in
            guard case let .checked(basis, bound) = status(of: check) else { return nil }
            let detail = [basis, bound].compactMap(\.self).joined(separator: "; ")
            return detail.isEmpty ? check.name : "\(check.name) (\(detail))"
        }
        let unchecked = CheckupCheck.allCases.compactMap { check -> String? in
            guard case let .notChecked(reason) = status(of: check) else { return nil }
            return "\(check.name) (\(reason))"
        }
        return [
            checked.isEmpty ? nil : "checked: " + checked.joined(separator: ", "),
            unchecked.isEmpty ? nil : "not checked: " + unchecked.joined(separator: ", "),
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}
