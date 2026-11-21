//
// Copyright © Agulhas Labs
//

import Foundation

extension RunFailureCensus {
    /// `note` without the expansion lines that only repeat what the failure already says, or `note` itself where none do.
    ///
    /// Two rules drop a line, both read over the expansion only: a string literal's expansion as itself (or an array literal of such literals as its source renders them), and a `some → V` that repeats its parent's value or cannot be its parent's own payload (see `Docs/Design.md`, "An expansion does not echo the literals it compares against"). A dropped line takes the unmarked lines beneath it.
    static func droppingEchoes(message: String, note: [NoteLine]) -> [NoteLine] {
        guard let echoes = RunExpansionEchoes(message: message, note: note) else {
            return note
        }
        let dropped = echoes.droppedPositions()
        return dropped.isEmpty ? note : note.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
    }
}

/// The expansion of one failed expectation, read as lines with a depth, an expression and a value.
struct RunExpansionEchoes {
    private let entries: [Entry]

    /// The expansion of `note` as `message` opens it, or `nil` where no `↳` line repeats the message's expression.
    init?(message: String, note: [RunFailureCensus.NoteLine]) {
        guard let start = note.firstIndex(where: { $0.marked && RunFailureShape.merging(message, with: $0.text) != nil }) else {
            return nil
        }
        var entries: [Entry] = []
        var position = start
        while position < note.count {
            var end = position + 1
            while end < note.count, !note[end].marked {
                end += 1
            }
            let text = note[position].text
            let arrow = RunFailureShape.firstArrow(in: text)
            let first = arrow.map { String(text[$0.upperBound...]) }
            let value = first.map { Self.normalized([$0] + note[position + 1 ..< end].map(\.text)) }
            entries.append(Entry(range: position ..< end, depth: note[position].indent.count, expression: arrow.map { String(text[..<$0.lowerBound]) } ?? text, value: value))
            position = end
        }
        self.entries = entries
    }

    /// The positions in the note of every line the two rules drop.
    func droppedPositions() -> Set<Int> {
        var dropped: Set<Int> = []
        for (offset, entry) in entries.enumerated() where selfExpands(entry) || echoesSome(entry, at: offset) {
            dropped.formUnion(entry.range)
        }
        return dropped
    }

    /// Whether the line's expression is one string literal, with no interpolation, and its value that literal's contents in double quotes; or an array literal of such literals (nested arrays too) and its value the rendering of its source.
    private func selfExpands(_ entry: Entry) -> Bool {
        if let value = entry.value, let rendering = Self.arrayRendering(of: entry.expression) {
            return value == Self.normalized([rendering])
        }
        guard let value = entry.value, let literal = Self.literal(at: entry.expression.startIndex, in: entry.expression),
              literal.end == entry.expression.endIndex, let contents = literal.contents
        else {
            return false
        }
        return value == Self.normalized(Self.quoted(contents))
    }

    /// Whether the line reads `some → V`, `V` not `nil`, and either repeats its parent's value or cannot be its parent's own Optional payload: its parent prints `nil`, already has a `some` line beneath it, or there is no parent.
    private func echoesSome(_ entry: Entry, at offset: Int) -> Bool {
        guard entry.expression == "some", let value = entry.value, value != Self.normalized(["nil"]) else {
            return false
        }
        guard let parent = parent(of: offset) else {
            return true
        }
        if entries[parent].value == value {
            return true
        }
        let hasSome = entries[parent + 1 ..< offset].contains { $0.expression == "some" && $0.depth == entry.depth }
        return entries[parent].value == Self.normalized(["nil"]) || hasSome
    }

    /// The nearest line above `offset` printed one level, two columns, shallower, dropped or not.
    private func parent(of offset: Int) -> Int? {
        let wanted = entries[offset].depth - 2
        for candidate in entries[..<offset].indices.reversed() {
            if entries[candidate].depth == wanted {
                return candidate
            }
            if entries[candidate].depth < wanted {
                return nil
            }
        }
        return nil
    }
}

private extension RunExpansionEchoes {
    /// One `↳` line with the unmarked lines beneath it: where it sits in the note, how deep the log printed it, and the expression and value either side of its first arrow.
    struct Entry {
        let range: Range<Int>
        let depth: Int
        let expression: String
        let value: [[Unicode.Scalar]]?
    }

    /// `lines` each trimmed of leading and trailing whitespace, as Unicode scalars, so values compare exactly and line by line.
    static func normalized(_ lines: [String]) -> [[Unicode.Scalar]] {
        lines.flatMap { $0.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) }.map { line in
            var trimmed = Array(line.drop { $0.properties.isWhitespace })
            while let last = trimmed.last, last.properties.isWhitespace {
                trimmed.removeLast()
            }
            return trimmed
        }
    }

    /// `contents` in double quotes, the way Swift Testing prints a string.
    static func quoted(_ contents: String) -> [String] {
        ["\"\(contents)\""]
    }

    /// The string literal opening at `index`: where it ends and its decoded contents, `nil` contents where it interpolates, holds an escape not decoded; `nil` where none opens.
    static func literal(at index: String.Index, in text: String) -> (end: String.Index, contents: String?)? {
        guard index < text.endIndex, let extent = RunDominantFailureClass.literal(in: text, openingAt: index) else {
            return nil
        }
        let hashes = text[index...].prefix { $0 == "#" }.count
        let opening = text.index(index, offsetBy: hashes)
        guard !extent.interpolates else {
            return (extent.end, nil)
        }
        let body = String(text[text.index(after: opening) ..< text.index(extent.end, offsetBy: -(1 + hashes))])
        if hashes > 0 {
            return (extent.end, body.contains("\\" + String(repeating: "#", count: hashes)) ? nil : body)
        }
        return (extent.end, decoded(body))
    }

    /// The rendering of `text` as an array literal of string literals, `[`, each element rendered and joined by `, `, `]`; `nil` where `text` is not exactly one, or an element holds an interpolation, an undecoded escape or a scalar `debugDescription` writes as `\u{…}`.
    static func arrayRendering(of text: String) -> String? {
        let scalars = text.unicodeScalars
        let start = skippingSpace(in: text, from: scalars.startIndex)
        guard let array = arrayLiteral(in: text, at: start) else {
            return nil
        }
        return skippingSpace(in: text, from: array.end) == scalars.endIndex ? array.rendering : nil
    }

    private static func arrayLiteral(in text: String, at start: String.Index) -> (end: String.Index, rendering: String)? {
        let scalars = text.unicodeScalars
        guard start < scalars.endIndex, scalars[start] == "[" else {
            return nil
        }
        var index = skippingSpace(in: text, from: scalars.index(after: start))
        var parts: [String] = []
        while index < scalars.endIndex {
            if scalars[index] == "]" {
                return (scalars.index(after: index), "[" + parts.joined(separator: ", ") + "]")
            }
            guard parts.isEmpty || scalars[index] == "," else {
                return nil
            }
            if !parts.isEmpty {
                index = skippingSpace(in: text, from: scalars.index(after: index))
                if index < scalars.endIndex, scalars[index] == "]" {
                    continue
                }
            }
            guard index < scalars.endIndex else {
                return nil
            }
            if scalars[index] == "[" {
                guard let nested = arrayLiteral(in: text, at: index) else {
                    return nil
                }
                parts.append(nested.rendering)
                index = nested.end
            } else {
                guard let element = literal(at: index, in: text), let contents = element.contents, let rendering = debugQuoted(contents) else {
                    return nil
                }
                parts.append(rendering)
                index = element.end
            }
            index = skippingSpace(in: text, from: index)
        }
        return nil
    }

    private static func skippingSpace(in text: String, from index: String.Index) -> String.Index {
        var index = index
        while index < text.unicodeScalars.endIndex, text.unicodeScalars[index].properties.isWhitespace {
            index = text.unicodeScalars.index(after: index)
        }
        return index
    }

    /// `contents` quoted the way `String.debugDescription` does, or `nil` where it holds a scalar that writes as `\u{…}`: a control scalar other than tab, newline, return and NUL, U+007F, or a grapheme-extending scalar.
    private static func debugQuoted(_ contents: String) -> String? {
        var result = "\""
        for scalar in contents.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case "\0": result += "\\0"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || scalar.properties.isGraphemeExtend {
                    return nil
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    /// `body` with its escapes `\n \t \r \0 \\ \" \'` and `\u{…}` decoded, or `nil` where it holds any other.
    static func decoded(_ body: String) -> String? {
        var result = String.UnicodeScalarView()
        var scalars = body.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\\" else {
                result.append(scalar)
                continue
            }
            guard let escaped = scalars.next() else {
                return nil
            }
            switch escaped {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "0": result.append("\0")
            case "\\", "\"", "'": result.append(escaped)
            case "u":
                guard scalars.next() == "{" else {
                    return nil
                }
                var hex = ""
                while let next = scalars.next(), next != "}" {
                    hex.unicodeScalars.append(next)
                }
                guard let code = UInt32(hex, radix: 16), let unicode = Unicode.Scalar(code) else {
                    return nil
                }
                result.append(unicode)
            default:
                return nil
            }
        }
        return String(result)
    }
}
