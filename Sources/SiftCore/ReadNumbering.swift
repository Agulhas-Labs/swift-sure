//
// Copyright © Agulhas Labs
//

import Foundation

/// Source lines laid out as Claude Code's Read lays them out, so an answer's lines can be read in place of a Read of the same lines.
struct ReadNumbering {
    /// The width a line number is right-aligned to, as Read aligns it.
    static var numberWidth: Int {
        6
    }

    /// Each line's number right-aligned to `numberWidth`, then a tab, then the source line.
    ///
    /// The `cited` line, where there is one, has `>` in place of its number's leading padding character, or before the number where it has none.
    static func numbered(_ page: [String], from first: Int, cited: Int?) -> [String] {
        var lineNumber = first - 1
        return page.map { line in
            lineNumber += 1
            let digits = String(lineNumber)
            let padded = String(repeating: " ", count: max(0, numberWidth - digits.count)) + digits
            let label = lineNumber == cited ? (padded.hasPrefix(" ") ? ">" + padded.dropFirst() : ">" + padded) : padded
            return label + "\t" + line
        }
    }
}
