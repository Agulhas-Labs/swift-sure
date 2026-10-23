//
// Copyright © Agulhas Labs
//

/// The `search` answer past `SearchRenderer.groupThreshold` matches at offset 0 (Docs/Design.md, *search past 40 matches*).
struct GroupedSearchAnswer {
    /// Files the grouped form lists before folding the rest into one line.
    static var groupedFileCap: Int {
        12
    }

    /// Whole-name rows the grouped form lists under the files.
    static var groupedRowCap: Int {
        5
    }

    /// The answer past the threshold at offset 0: the summary, up to `groupedFileCap` files by match count, the whole-name matches as rows, and the line saying how to narrow or continue.
    static func lines(result: StructuralSearch.Result) -> [String] {
        var counts: [String: Int] = [:]
        for match in result.matches {
            counts[match.path, default: 0] += 1
        }
        let files = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let summary = "\(result.matches.count) declaration(s) in \(files.count) file(s) — scanned \(result.filesScanned) file(s); grouped by file past \(SearchRenderer.groupThreshold)"
        var lines = [summary]
        let width = String(files.first?.value ?? 0).count
        for (path, count) in files.prefix(groupedFileCap) {
            lines.append("  " + String(repeating: " ", count: width - String(count).count) + String(count) + "  " + path)
        }
        let folded = files.dropFirst(groupedFileCap)
        if !folded.isEmpty {
            lines.append("  + \(folded.count) more files (\(folded.reduce(0) { $0 + $1.value }) matches)")
        }

        let whole = Array(result.matches.prefix(result.wholeNameMatches))
        let rows = Array((whole.isEmpty ? result.matches : whole).prefix(groupedRowCap))
        lines.append(whole.isEmpty ? "first \(rows.count):" : "whole-name matches (\(whole.count)):")
        var currentPath = ""
        for match in rows {
            if match.path != currentPath {
                currentPath = match.path
                lines.append(currentPath + ":")
            }
            lines.append("  :\(match.line)-\(match.endLine)  \(match.qualifiedName) — \(SourceSlicer.shown(match.signature))")
        }
        let basename = files.first.map { $0.key.split(separator: "/").last.map(String.init) ?? $0.key } ?? ""
        let pathValue = basename.contains(where: \.isWhitespace) ? "\"\(basename)\"" : basename
        lines.append("narrow with path:\(pathValue), owner:<Type>, kind:, or a tighter name:; offset \(rows.count) continues the listing")
        return lines
    }
}
