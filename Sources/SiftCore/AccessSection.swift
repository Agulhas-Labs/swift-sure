//
// Copyright © Agulhas Labs
//

/// Renders `diff`'s access section: a verdict per level, then the declarations counted in it, the ones never judged and the ones past the lookup budget.
///
/// It is a finding about the change, never a lint: a name-matched declaration is said to have no use *by that name*, never to be unused, since a name match can miss a use through a typealias, a closure or a macro.
struct AccessSection {
    /// Per-declaration lines shown before the rest are named on one `+N more` line.
    static var lineCap: Int {
        10
    }

    static func lines(_ report: AccessReport) -> [String] {
        let findings = report.findings
        let shown = levels(of: findings)
        let counted = findings.filter { $0.verdict != .needsLevel }
        var lines = [""]
        lines.append(verdictLine(findings) ?? "access: none of the declarations this range put at open, public or package could be judged")
        lines += resolutionLines(findings)
        lines += publishedLines(findings)
        for level in shown {
            let widened = findings.filter { $0.subject.level == level && $0.subject.widened }
            guard !widened.isEmpty else { continue }
            let verb = widened.count == 1 ? "was" : "were"
            lines.append("  \(widened.count) of the \(level.rawValue) declarations \(verb) widened, not added: \(widened.map(qualified).joined(separator: ", "))")
        }
        lines += counted.prefix(lineCap).map(declarationLine)
        if counted.count > lineCap {
            lines.append("  +\(counted.count - lineCap) more: \(counted.dropFirst(lineCap).map(qualified).joined(separator: ", "))")
        }
        if !report.notJudged.isEmpty {
            lines.append("  not judged: \(report.notJudged.sorted { $0.key < $1.key }.map { $0.key.label($0.value) }.joined(separator: ", "))")
        }
        if report.notChecked > 0 {
            lines.append("  not checked: \(report.notChecked) more (over the first \(AccessLookup.lookupCap))")
        }
        return lines
    }
}

extension AccessSection {
    /// The verdict line as `diff` prints it, `nil` where nothing was judged.
    static func verdictLine(_ findings: [AccessFinding]) -> String? {
        guard !findings.isEmpty else { return nil }
        let shown = levels(of: findings)
        if findings.allSatisfy({ $0.verdict == .needsLevel }) {
            let parts = shown.enumerated().map { index, level in
                let count = findings.count { $0.subject.level == level }
                return index == 0 ? "\(count) \(count == 1 ? "declaration" : "declarations") at \(level.rawValue)" : "\(count) at \(level.rawValue)"
            }
            return "access: this range put \(parts.joined(separator: ", ")); each has a use that needs its level"
        }
        return "access: this range put " + shown.enumerated().map { verdict(for: $1, first: $0 == 0, in: findings) }.joined(separator: "; ")
    }

    /// The question lines for the library products whose public declarations are counted.
    static func publishedLines(_ findings: [AccessFinding]) -> [String] {
        let counted = findings.filter { $0.verdict != .needsLevel }
        let published = Set(counted.filter { $0.published && $0.subject.level == .publicLevel }.map(\.module)).sorted()
        return published.map { "  \($0) is a library product this repository publishes: its public API may serve consumers this repository does not contain" }
    }
}

private extension AccessSection {
    static func levels(of findings: [AccessFinding]) -> [AccessLevel] {
        [AccessLevel.publicLevel, .packageLevel].filter { level in findings.contains { $0.subject.level == level } }
    }

    static func qualified(_ finding: AccessFinding) -> String {
        "\(finding.module).\(finding.subject.label)"
    }

    /// One level's part of the verdict line: its subjects, those with no use outside their module and, for `public`, those used only inside its package.
    static func verdict(for level: AccessLevel, first: Bool, in findings: [AccessFinding]) -> String {
        let atLevel = findings.filter { $0.subject.level == level }
        let modules = Set(atLevel.map(\.module))
        let outside = modules.count == 1 ? "module \(modules.first ?? "")" : "their module"
        let noUse = atLevel.count {
            if case .noUse = $0.verdict {
                true
            } else {
                false
            }
        }
        let packageOnly = atLevel.count {
            if case .packageOnly = $0.verdict {
                true
            } else {
                false
            }
        }
        var text = first ? "\(atLevel.count) \(atLevel.count == 1 ? "declaration" : "declarations") at \(level.rawValue)" : "\(atLevel.count) at \(level.rawValue)"
        if noUse > 0 {
            text += ", \(noUse) with no use outside \(outside)"
        }
        if packageOnly > 0 {
            text += ", \(packageOnly) used only inside its package"
        }
        if noUse == 0, packageOnly == 0 {
            text += ", each with a use that needs its level"
        }
        return text
    }

    /// How the uses were found, in the callers section's words, naming the name-matched declarations where the two modes mix.
    ///
    /// Where the store resolved them, the files it does not cover whose matches by name were counted beside its uses are named on the same line.
    static func resolutionLines(_ findings: [AccessFinding]) -> [String] {
        let nameMatched = findings.filter { $0.nameMatchedOn != nil }
        if nameMatched.isEmpty {
            return findings.isEmpty ? [] : ["  uses resolved by the index store, in the targets the last build compiled" + uncoveredClause(findings)]
        }
        if nameMatched.count == findings.count {
            return ["  uses name-matched over the working tree, which can miss a use through a typealias, a closure or a macro"]
        }
        return ["  uses resolved by the index store, except name-matched over the working tree for: \(nameMatched.map(qualified).joined(separator: ", "))" + uncoveredClause(findings)]
    }

    /// `; name-matched in the files the last build left out or that changed since: …`, naming at most ``lineCap`` of them, or `; name-matched in N files …` where none held a match, or nothing where the store covers every file.
    static func uncoveredClause(_ findings: [AccessFinding]) -> String {
        let files = Set(findings.flatMap(\.nameMatchedFiles)).sorted()
        guard !files.isEmpty else {
            let count = findings.map(\.uncoveredFileCount).max() ?? 0
            guard count > 0 else { return "" }
            return "; name-matched in \(count) \(count == 1 ? "file" : "files") the last build left out or that changed since"
        }
        let more = files.count > lineCap ? ", +\(files.count - lineCap) more" : ""
        return "; name-matched in the files the last build left out or that changed since: \(files.prefix(lineCap).joined(separator: ", "))\(more)"
    }

    static func declarationLine(_ finding: AccessFinding) -> String {
        let subject = finding.subject
        let question = finding.published && subject.level == .publicLevel ? "?" : ""
        let reason = switch finding.verdict {
        case .noUse(testable: true): "used only from tests, which import it @testable"
        case .noUse: finding.nameMatchedOn == nil ? "no use outside module \(finding.module)" : "no use by that name outside module \(finding.module)"
        case let .packageOnly(users): "used only from \(users.joined(separator: ", ")), in this package"
        case .needsLevel: ""
        }
        let suggestion = finding.verdict.suggestion?.rawValue ?? subject.level.rawValue
        return "  \(subject.widened ? "~" : "+") \(qualified(finding))  \(subject.path):\(subject.line)  \(subject.level.rawValue) → \(suggestion)\(question): \(reason)"
    }
}
