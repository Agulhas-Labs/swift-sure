//
// Copyright © Agulhas Labs
//

import Foundation

/// The `callers` check: `diff`'s callers section, with the sites on lines the range edited left out.
struct CheckupCallersCheck {
    let gatherer: DiffGatherer
    let range: DiffRange
    /// The `diff` command each finding points to: over the range the checkup was given, bare where none was.
    let diffCommand: String

    /// One finding per member that a line the range did not edit still spells, the members taken in path then line order up to the cap; a bound that stopped the lookup counts what it left out.
    func outcome(files: [FileDiff], semantic: SemanticInput) async throws -> CheckupOutcome {
        let subjects = DiffGatherer.callerSubjects(files: files)
            .filter { Self.verb(for: $0.change) != nil }
            .sorted { ($0.target.path, $0.target.line, $0.target.label) < ($1.target.path, $1.target.line, $1.target.label) }
        guard !subjects.isEmpty else { return CheckupOutcome(check: .callers, status: .checked(basis: nil, bound: nil), findings: []) }
        let looked = Array(subjects.prefix(DiffCallers.memberCap))
        let reports = try await gatherer.callers(of: looked.map(\.target), semantic: semantic)
        var edits = Edits(gatherer: gatherer, range: range, files: files)
        var findings: [CheckupFinding] = []
        for (subject, report) in zip(looked, reports) {
            let remaining = report.sites.filter { !edits.edited($0) }
            guard let first = remaining.first, let verb = Self.verb(for: subject.change) else { continue }
            let target = subject.target
            let count = remaining.count == 1 ? "1 caller" : "\(remaining.count) callers"
            let matched = report.unresolvedBecause == nil ? "" : " (name-matched)"
            findings.append(CheckupFinding(
                findingClass: .callers,
                path: target.path,
                line: target.line,
                endLine: nil,
                text: "\(target.label) \(verb); \(count) on lines this change did not edit, first \(first.path):\(first.line)\(matched)",
                command: diffCommand
            ))
        }
        let skipped = subjects.count - looked.count
        return CheckupOutcome(
            check: .callers,
            status: .checked(basis: Self.basis(reports, semantic: semantic), bound: skipped > 0 ? "\(looked.count) of \(subjects.count) members; \(skipped) not looked up" : nil),
            findings: findings
        )
    }

    /// What happened to a subject: removed, signature changed or narrowed; `nil` for a widening, which is no subject.
    ///
    /// An access keyword is part of the recorded signature, so a signature counts as changed only where it differs apart from them.
    static func verb(for change: DeclarationChange) -> String? {
        if change.kind == .removed {
            return "removed"
        }
        if change.signatureChanged, withoutAccess(change.oldSignature) != withoutAccess(change.newSignature) {
            return "signature changed"
        }
        if let before = change.oldAccess, let after = change.newAccess, after < before {
            return "narrowed"
        }
        return nil
    }

    private static func withoutAccess(_ signature: String?) -> [Substring] {
        let keywords = Set(AccessLevel.allCases.map(\.rawValue))
        return (signature ?? "").split(separator: " ").filter { !keywords.contains(String($0)) }
    }

    /// The resolution `diff`'s heading words: all store-resolved, or the store's state with the number of name-matched members.
    static func basis(_ reports: [DiffCallers.Report], semantic: SemanticInput) -> String {
        let matched = reports.count { $0.unresolvedBecause != nil }
        guard matched > 0 else { return "store-resolved" }
        if case .active = semantic {
            return "store open; \(matched) name-matched"
        }
        return "no store; \(matched) name-matched"
    }
}

private extension CheckupCallersCheck {
    /// The edited lines of each file a caller site was found in, read once per file.
    struct Edits {
        let gatherer: DiffGatherer
        let range: DiffRange
        let files: [String: FileDiff]
        private var cache: [String: CheckupEditedLines?] = [:]

        init(gatherer: DiffGatherer, range: DiffRange, files: [FileDiff]) {
            self.gatherer = gatherer
            self.range = range
            self.files = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
        }

        mutating func edited(_ site: DiffCallers.Site) -> Bool {
            if cache[site.path] == nil {
                cache[site.path] = .some(lines(of: site.path))
            }
            return cache[site.path].flatMap(\.self)?.contains(workingTreeLine: site.line) ?? false
        }

        private func lines(of path: String) -> CheckupEditedLines? {
            guard let file = files[path] else { return nil }
            let from: String = if case let .renamed(old) = file.status {
                old
            } else {
                path
            }
            let onDisk = try? Data(contentsOf: gatherer.repoRoot.appendingPathComponent(path))
            var requests = [(rev: range.from, path: from)]
            if case let .revision(rev) = range.to {
                requests.append((rev: rev, path: path))
            }
            guard let blobs = try? gatherer.git.blobs(requests) else { return nil }
            if case .revision = range.to {
                return CheckupEditedLines(before: blobs[0], after: blobs[1], workingTree: onDisk)
            }
            return CheckupEditedLines(before: blobs[0], after: onDisk, workingTree: nil)
        }
    }
}
