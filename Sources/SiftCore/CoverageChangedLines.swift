//
// Copyright © Agulhas Labs
//

import Foundation

/// The line that opens the coverage section: how many of the lines the change touched are executable, how many of those ran, and where the others are.
public struct CoverageChangedLines {
    private init() {}

    /// The most uncovered ranges the line names before it says how many more there are.
    static let rangeLimit = 5

    /// The `changed lines:` line, or `nil` where the change touched no line of any file.
    ///
    /// - Parameters:
    ///   - changed: Each changed file's after-side lines, keyed by repository-relative path.
    ///   - counts: Each measured file's executable lines and their counts; a line absent from it is not executable, and a file absent from it was not measured.
    static func line(changed: [String: Set<Int>], counts: [String: [Int: UInt64]]) -> String? {
        guard !changed.isEmpty else { return nil }
        var executable = 0
        var covered = 0
        var uncovered: [String] = []
        var measured = false
        for path in changed.keys.sorted() {
            guard let fileCounts = counts[path] else { continue }
            measured = true
            let lines = changed[path, default: []].filter { fileCounts[$0] != nil }.sorted()
            executable += lines.count
            let notRun = lines.filter { fileCounts[$0] == 0 }
            covered += lines.count - notRun.count
            uncovered += CoverageAnswer.ranges(notRun).split(separator: ",").map { "\(path)\($0.trimmingCharacters(in: .whitespaces))" }
        }
        guard measured else { return "changed lines: none measured" }
        guard executable > 0 else { return "changed lines: none executable" }
        var named = Array(uncovered.prefix(rangeLimit))
        if uncovered.count > rangeLimit {
            named.append("+\(uncovered.count - rangeLimit) more")
        }
        let tail = named.isEmpty ? "" : "; uncovered: \(named.joined(separator: ", "))"
        return "changed lines: \(executable) executable, \(covered) covered\(tail)"
    }
}
