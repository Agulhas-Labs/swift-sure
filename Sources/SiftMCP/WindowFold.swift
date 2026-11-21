//
// Copyright © Agulhas Labs
//

import Foundation

/// A shell window's lines as the command prints them, with each run of two or more comment lines folded to one marker line.
public struct WindowFold: Equatable, Sendable {
    /// The folded output.
    public let text: String
    /// The UTF-8 bytes the command itself prints, numbering included and nothing folded.
    public let printedBytes: Int
    /// The comment lines folded away.
    public let foldedLines: Int
    /// The marker lines written.
    public let runs: Int

    /// Folds `lines` (clipped to the file's end) of `fileText`.
    ///
    /// `commentLines` holds the file's line numbers that are only a line comment. The result is `nil` where the window cannot be rendered exactly: an `nl` input holding a section delimiter.
    public static func fold(
        fileText: String,
        lines: ClosedRange<Int>,
        numbering: WindowNumbering,
        commentLines: Set<Int>
    ) -> WindowFold? {
        // Split on scalars: a CRLF is one Character, which a Character split would not cut at.
        let fileLines = fileText.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
        let endsWithNewline = fileText.utf8.last == UInt8(ascii: "\n")
        let total = endsWithNewline ? fileLines.count - 1 : fileLines.count
        let last = min(lines.upperBound, total)
        guard lines.lowerBound >= 1, lines.lowerBound <= last else {
            return WindowFold(text: "", printedBytes: 0, foldedLines: 0, runs: 0)
        }
        var printed = [(number: String, body: String, isComment: Bool)]()
        var counter = numberingStart(numbering)
        for index in lines.lowerBound ... last {
            let body = fileLines[index - 1]
            var prefix = ""
            var label = ""
            switch numbering {
            case .none:
                label = String(index)
            case .catN:
                label = String(counter)
                prefix = pad(counter)
                counter += 1
            case let .numberLines(_, numbersBlank):
                if body == "\\:" || body == "\\:\\:" || body == "\\:\\:\\:" {
                    return nil
                }
                if body.isEmpty, !numbersBlank {
                    prefix = String(repeating: " ", count: 6) + "\t"
                } else {
                    label = String(counter)
                    prefix = pad(counter)
                    counter += 1
                }
            case let .awk(_, separator):
                label = String(counter)
                prefix = "\(counter)\(separator)"
                counter += 1
            }
            printed.append((label, prefix + body, commentLines.contains(index)))
        }
        let closesWithNewline: Bool = {
            if case .awk = numbering {
                return true
            }
            return last < total || endsWithNewline
        }()
        let terminator = closesWithNewline ? "\n" : ""
        let printedText = printed.map(\.body).joined(separator: "\n") + terminator
        var out = ""
        var foldedLines = 0
        var runs = 0
        var cursor = 0
        while cursor < printed.count {
            var end = cursor
            if printed[cursor].isComment {
                while end + 1 < printed.count, printed[end + 1].isComment {
                    end += 1
                }
            }
            let count = end - cursor + 1
            if count >= 2 {
                out += "\(printed[cursor].number)-\(printed[end].number): // … \(count) comment lines\n"
                foldedLines += count
                runs += 1
            } else {
                out += printed[cursor].body
                out += cursor == printed.count - 1 ? terminator : "\n"
            }
            cursor = end + 1
        }
        return WindowFold(text: out, printedBytes: printedText.utf8.count, foldedLines: foldedLines, runs: runs)
    }

    private static func numberingStart(_ numbering: WindowNumbering) -> Int {
        switch numbering {
        case .none: 1
        case let .catN(first): first
        case let .numberLines(first, _): first
        case let .awk(first, _): first
        }
    }

    private static func pad(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: " ", count: max(0, 6 - digits.count)) + digits + "\t"
    }
}
