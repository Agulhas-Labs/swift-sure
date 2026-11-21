//
// Copyright © Agulhas Labs
//

import Foundation

/// A shell line read leg by leg for the comment fold: each statement a window of one Swift file, an `echo` of literal words, or anything else.
///
/// A window is a pipeline whose stages are on ``FallbackProof``'s closed list, the first reading one `.swift` file, optionally followed by one numbering stage: `cat -n`, `nl` or `nl -ba` with no other option, or `awk '{print NR+k"<sep>"$0}'`. A numbering stage is display, not a filter, so it is read off here and the window is the stages in front of it.
public struct ShellWindowLine: Equatable, Sendable {
    /// The legs, in the order the shell runs them.
    public let legs: [Leg]

    /// The windows on the line, in order.
    public var windows: [Window] {
        legs.compactMap {
            if case let .window(window) = $0 {
                window
            } else {
                nil
            }
        }
    }

    /// Whether a leg is neither a window nor an `echo`, so the line cannot be served without running it.
    public var runsOthers: Bool {
        legs.contains(.other)
    }

    /// `command` read leg by leg, or `nil` where it holds no window of a Swift file, or joins its statements by anything but `;`, `&&` or line breaks, a trailing `|| true` aside.
    ///
    /// A statement that prints nothing and that the compound rules already reproduce (``InPlaceShape``: a `cd`, an assignment, `export`, `unset`, `set`, a trailing `|| true` or `|| :`) is no leg: the line is weighed as if it were absent, and a window after a `cd` names its file as read from where the `cd` moved.
    public static func reading(_ command: String) -> Self? {
        let ranges = ShellSyntax.statementRanges(of: command)
        guard !ranges.isEmpty else { return nil }
        var cursor = command.startIndex
        var joints: [String] = []
        for (_, range) in ranges {
            joints.append(command[cursor ..< range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines))
            cursor = range.upperBound
        }
        let tail = command[cursor...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.isEmpty || tail == ";" else { return nil }
        var statements = ranges.map(\.statement)
        // The windows before a trailing silent fallback print the same whether or not it runs.
        if joints.count > 1, joints.last == "||", let last = statements.last, InPlaceShape.isSilentFallback(last) {
            joints.removeLast()
            statements.removeLast()
        }
        guard joints.allSatisfy({ $0.isEmpty || $0 == ";" || $0 == "&&" }) else { return nil }
        let legs = legs(of: statements)
        guard legs.contains(where: {
            if case .window = $0 {
                true
            } else {
                false
            }
        }) else { return nil }
        return Self(legs: legs)
    }

    /// `command` as ``reading(_:)`` reads it where that reads it at all; otherwise, where a statement on it is a window of a Swift file but the statements are joined by something else (`||`, `&`), its legs with one more ``Leg/other`` leg standing for that join, which decides what runs, so the line is one that ``runsOthers``.
    ///
    /// `nil` where no statement is such a window.
    public static func readingAnyJoin(_ command: String) -> Self? {
        if let line = reading(command) {
            return line
        }
        let legs = legs(of: ShellSyntax.statementRanges(of: command).map(\.statement))
        let line = Self(legs: legs + [.other])
        return line.windows.isEmpty ? nil : line
    }

    /// This line with every window `isOther` holds read as an ``Leg/other`` leg: a window the caller reads as something else, such as one reaching every line of its file, which is a whole read.
    public func reading(asOther isOther: (Window) -> Bool) -> Self {
        Self(legs: legs.map { leg in
            if case let .window(window) = leg, isOther(window) {
                return .other
            }
            return leg
        })
    }

    /// The legs `statements` are, in order: a `cd` to a directory it names moves where every later window's file is read from, and a `cd` it does not (`cd -`, `pushd`) is an ``Leg/other`` leg; an assignment, `export`, `unset` or `set` is no leg, unless it prints the shell's state (``InPlaceShape/setsNothingVisible(_:)``).
    static func legs(of statements: [String]) -> [Leg] {
        var moved: String?
        var legs: [Leg] = []
        for statement in statements {
            if InPlaceShape.movesDirectory(statement) {
                guard let target = InPlaceShape.changeOfDirectory(statement) else {
                    legs.append(.other)
                    continue
                }
                moved = path(target, from: moved)
                continue
            }
            guard !InPlaceShape.setsNothingVisible(statement) else { continue }
            legs.append(leg(of: statement, movedTo: moved))
        }
        return legs
    }

    /// The leg `statement` is, its file read from `moved`, where a `cd` before it on the line moved, as written.
    ///
    /// A `cat` of several files into a window is a window of its first file that ``Window/printed(of:)`` never renders: its lines are not one file's.
    static func leg(of statement: String, movedTo moved: String? = nil) -> Leg {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = ShellSyntax.segments(of: trimmed)
        // The redirections ``FallbackProof`` allows send nothing a window prints elsewhere, so each stage is read without them: a stage's last word is its operand.
        let stages = segments.map { ShellQuery($0).invocation.filter { $0 != "2>/dev/null" && $0 != "2>&1" } }
        if stages.count == 1, let printed = echoed(stages[0], written: trimmed) {
            return .echo(printed)
        }
        guard let first = stages.first, first.count >= 2 else { return .other }
        var windowStages = stages
        var trailing: (start: Int, stage: Stage)?
        if stages.count >= 2, let numbering = numberingStage(stages[stages.count - 1]) {
            windowStages.removeLast()
            trailing = numbering
        }
        let several = windowStages.count > 1 ? InPlaceShape.multiFileReads(segments[0]).flatMap { $0.count > 1 ? $0 : nil } : nil
        // Every file being there, a `cat` of several exits as a `cat` of its first does.
        let proven = several.map { [[first[0]] + (SeveralFileCat.numbersLines(segments[0]) ? ["-n"] : []) + [$0[0]]] + windowStages.dropFirst() } ?? windowStages
        // A lone `nl F` is no window: it prints the whole file, and no lookup is made of it.
        guard first[0] != "nl" || windowStages.count > 1 else { return .other }
        guard FallbackProof.isProvenWindow(proven), let written = several?.first ?? first.last, written.hasSuffix(".swift") else { return .other }
        let window = LineWindow(stages: windowStages)
        return .window(Window(path: path(written, from: moved), statement: trimmed, window: window, numbers: numbers(of: windowStages, trailing: trailing), catsSeveralFiles: several != nil))
    }

    /// `written`, a path as a statement spells it, as read from `moved`, the directory a `cd` before it moved to as written; `written` itself where nothing moved or it is absolute.
    private static func path(_ written: String, from moved: String?) -> String {
        guard let moved, !written.hasPrefix("/") else { return written }
        return (moved as NSString).appendingPathComponent(written)
    }

    /// How `stages`, with `trailing` after them, number what they print, or `nil` where it is not rendered exactly.
    private static func numbers(of stages: [[String]], trailing: (start: Int, stage: Stage)?) -> Numbers? {
        // A numbering stage before a later filter numbers what that filter picks from: lines no rendering here reproduces.
        guard !stages.dropFirst().contains(where: { numberingStage($0) != nil }) else { return nil }
        let numbersItself: Numbers? = {
            let first = stages[0]
            if first[0] == "cat", first.contains("-n") {
                return .fileLines
            }
            if first[0] == "nl" {
                // `nl -ba F` numbers every file line as `cat -n` does; a bare `nl F` skips blank lines, so its numbers are not the file's.
                return first.count == 3 && first[1] == "-ba" ? .fileLines : nil
            }
            if first[0] == "awk" {
                return awkBody(first[1])
            }
            return Numbers.none
        }()
        // A later `awk` window prints by its own body too.
        let laterBodies = stages.dropFirst().filter { $0.first == "awk" }.map { awkBody($0[1]) }
        guard let numbersItself, laterBodies.allSatisfy({ $0 == Numbers.none }) else { return nil }
        guard let trailing else { return numbersItself }
        // Numbered twice is not rendered.
        guard numbersItself == .none else { return nil }
        return .printed(start: trailing.start, format: trailing.stage)
    }

    /// What an `awk` window's body prints: nothing beyond the line, the line numbered by `NR`, or `nil` for anything else.
    private static func awkBody(_ program: String) -> Numbers? {
        guard let open = program.firstIndex(of: "{") else { return Numbers.none }
        let body = program[open...]
        if body.wholeMatch(of: /\{\s*print\s*(?:\$0\s*)?;?\s*\}/) != nil || body.wholeMatch(of: ShellQuery.awkPrintfsEachLine) != nil {
            return Numbers.none
        }
        guard let match = body.wholeMatch(of: /\{\s*print\s+NR\s*"((?:[^"\\]|\\t)*)"\s*\$0\s*;?\s*\}/) else { return nil }
        return .awkFileLines(separator: String(match.1).replacingOccurrences(of: "\\t", with: "\t"))
    }

    /// The numbering stage `words` is, with the number its first line prints, or `nil` where it is none.
    static func numberingStage(_ words: [String]) -> (start: Int, stage: Stage)? {
        switch words {
        case ["cat", "-n"]:
            return (1, .catN)
        case ["nl"]:
            return (1, .numberLines(numbersBlank: false))
        case ["nl", "-ba"]:
            return (1, .numberLines(numbersBlank: true))
        default:
            guard words.count == 2, words[0] == "awk",
                  let match = words[1].wholeMatch(of: /\{\s*print\s+NR\s*(?:\+\s*([0-9]{1,9})\s*)?"((?:[^"\\]|\\t)*)"\s*\$0\s*;?\s*\}/)
            else { return nil }
            let offset = match.1.flatMap { Int($0) } ?? 0
            return (1 + offset, .awk(separator: String(match.2).replacingOccurrences(of: "\\t", with: "\t")))
        }
    }

    /// What an `echo` of literal words prints, or `nil` where `words` is anything else: an option, an escape, a character outside the closed list below (which keeps out every expansion and glob: a brace's `{a,b}`, zsh's `=cmd`, a `[ab]` zsh refuses as matching nothing), or a lone `-`, which zsh's `echo` takes as the end of its options and does not print.
    private static func echoed(_ words: [String], written: String) -> String? {
        guard words.first == "echo", written.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || " ._:/+,-'\"".contains($0)) }) else { return nil }
        let arguments = words.dropFirst()
        guard !arguments.contains(where: { $0 == "-" || $0.wholeMatch(of: /-[neE]+/) != nil }) else { return nil }
        return arguments.joined(separator: " ") + "\n"
    }
}

public extension ShellWindowLine {
    /// One statement of the line.
    enum Leg: Equatable, Sendable {
        case window(Window)
        /// An `echo` of literal words, with the text it prints.
        case echo(String)
        /// Any other statement: a search, a whole read, a window this cannot read, any other command.
        case other
    }

    /// A window of one Swift file, as the command spells it.
    struct Window: Equatable, Sendable {
        /// The file the first stage reads, as written.
        public let path: String
        /// The statement as written.
        public let statement: String
        /// The window's own stages, the numbering stage dropped.
        public let window: LineWindow
        /// How the printed lines are numbered, or `nil` where the command numbers them in a way not rendered byte for byte.
        public let numbers: Numbers?
        /// Whether the first stage is a `cat` of several files, so the window prints lines of them joined and ``path`` names only the first.
        public var catsSeveralFiles = false
    }

    /// How a window's command numbers what it prints, before the file is read.
    enum Numbers: Equatable, Sendable {
        case none
        /// `cat -n` reading the file: each line carries its own line number.
        case fileLines
        /// An `awk` window whose body prints `NR`, the separator, then the line.
        case awkFileLines(separator: String)
        /// A numbering stage after the window, counting the printed lines from `start`.
        case printed(start: Int, format: Stage)
    }

    /// A numbering stage's format.
    enum Stage: Equatable, Sendable {
        case catN
        case numberLines(numbersBlank: Bool)
        case awk(separator: String)
    }
}

public extension ShellWindowLine.Window {
    /// The lines this window prints of `fileText` and how they are numbered, or `nil` where they cannot be read off the command or rendered exactly: a `cat` of several files, a stage `LineWindow` cannot read, lines that are not one run, an unrendered numbering, an `awk` window ending a file that has no last newline.
    func printed(of fileText: String) -> (lines: ClosedRange<Int>, numbering: WindowNumbering)? {
        guard let numbers, !catsSeveralFiles else { return nil }
        var fileLines = fileText.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String(String.UnicodeScalarView($0)) }
        let endsWithNewline = fileText.utf8.last == UInt8(ascii: "\n")
        if endsWithNewline {
            fileLines.removeLast()
        }
        guard let picked = window.lines(in: fileLines), let low = picked.first, let high = picked.last,
              picked.count == high - low + 1
        else { return nil }
        let awkPrints = window.stages.contains { $0.first == "awk" }
        if awkPrints, high == fileLines.count, !endsWithNewline {
            return nil
        }
        let numbering: WindowNumbering = switch numbers {
        case .none: .none
        case .fileLines: .catN(first: low)
        case let .awkFileLines(separator): .awk(first: low, separator: separator)
        case let .printed(start, .catN): .catN(first: start)
        case let .printed(start, .numberLines(numbersBlank)): .numberLines(first: start, numbersBlank: numbersBlank)
        case let .printed(start, .awk(separator)): .awk(first: start, separator: separator)
        }
        return (low ... high, numbering)
    }
}
