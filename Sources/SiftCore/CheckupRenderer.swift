//
// Copyright © Agulhas Labs
//

/// Renders a `checkup` answer from the header, the range, the findings and the status of every check, and nothing else.
struct CheckupRenderer {
    /// The most finding lines one page carries.
    static let pageSize = 20

    let header: String
    /// What was compared, as `diff` words it.
    let range: String
    let changedFiles: Int
    let findings: [CheckupFinding]
    let checks: CheckupChecks
    let offset: Int

    /// The answer: on a first page the header, the verdict and the checks, then the findings; on a later page the header, the page and the findings only.
    func render() -> String {
        let ordered = findings.enumerated().sorted { lhs, rhs in
            let (left, right) = (lhs.element, rhs.element)
            if left.findingClass != right.findingClass {
                return left.findingClass < right.findingClass
            }
            if left.path != right.path {
                return (left.path ?? "") < (right.path ?? "")
            }
            if left.line != right.line {
                return (left.line ?? 0) < (right.line ?? 0)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let start = max(0, offset)
        let page = ordered.dropFirst(start).prefix(Self.pageSize)
        var lines = [header]
        if start == 0 {
            lines.append(verdict(ordered))
            lines.append(checks.rendered)
        } else {
            lines.append(laterPageLine(total: ordered.count, start: start))
        }
        lines += page.map(Self.line)
        let remaining = ordered.count - start - page.count
        if remaining > 0 {
            lines.append("truncated: \(remaining) more \(remaining == 1 ? "finding" : "findings") — pass --offset \(start + page.count)")
        }
        return lines.joined(separator: "\n")
    }

    private func verdict(_ ordered: [CheckupFinding]) -> String {
        let files = "\(changedFiles) changed \(changedFiles == 1 ? "file" : "files")"
        guard !ordered.isEmpty else { return "checkup: \(range) · nothing found over \(files)" }
        let counts = CheckupFindingClass.allCases.compactMap { kind -> String? in
            let count = ordered.filter { $0.findingClass == kind }.count
            return count == 0 ? nil : "\(count) \(kind.rawValue)"
        }
        let total = "\(ordered.count) \(ordered.count == 1 ? "finding" : "findings")"
        return "checkup: \(range) · \(total) over \(files) — \(counts.joined(separator: ", "))"
    }

    private func laterPageLine(total: Int, start: Int) -> String {
        guard start < total else { return "checkup: no findings at --offset \(start); \(total) in all" }
        let pages = (total + Self.pageSize - 1) / Self.pageSize
        return "checkup: page \(start / Self.pageSize + 1) of \(pages) — \(total) findings"
    }

    private static func line(_ finding: CheckupFinding) -> String {
        let label = finding.findingClass.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        let location = finding.location.map { $0 + "  " } ?? ""
        let command = finding.command.isEmpty ? "" : " — \(finding.command)"
        return "\(label)  \(location)\(finding.text)\(command)"
    }
}
