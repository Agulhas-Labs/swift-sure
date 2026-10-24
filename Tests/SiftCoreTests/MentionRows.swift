//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// The mention blocks of an answer folded back to the compact one-line form, for tests that pin which files and lines were listed, not the text beside them.
struct MentionRows {
    /// `answer` with each block of rows under a `…mention the name:` heading joined into the heading's compact line, `heading path:1,2 · path:3 · N outside files not scanned`.
    static func compacted(_ answer: String, sourceLocation: SourceLocation = #_sourceLocation) -> String {
        let rows = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            index += 1
            guard row.hasSuffix("mention the name:") else {
                out.append(row)
                continue
            }
            var entries: [String] = []
            while index < rows.count, rows[index].hasPrefix("  ") {
                let next = rows[index]
                index += 1
                if next.hasPrefix("    :") {
                    let number = next.dropFirst(5).prefix { $0.isNumber }
                    guard !entries.isEmpty else {
                        Issue.record("a row precedes any file heading: \(next)", sourceLocation: sourceLocation)
                        continue
                    }
                    entries[entries.count - 1] += (entries[entries.count - 1].hasSuffix(":") ? "" : ",") + number
                } else if next.hasSuffix("):"), let open = next.lastIndex(of: "(") {
                    entries.append(next.dropFirst(2).prefix(upTo: open).dropLast() + ":")
                } else {
                    entries.append(String(next.dropFirst(2)))
                }
            }
            out.append(row + " " + entries.joined(separator: " · "))
        }
        return out.joined(separator: "\n")
    }
}
