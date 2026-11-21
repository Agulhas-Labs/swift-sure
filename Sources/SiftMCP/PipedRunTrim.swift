//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// A build or test run whose pipeline only cuts its output down — `swift test 2>&1 | tail -40`, `swift-sure run -- swift test | head -4` — rewritten without the cut.
///
/// `swift-sure run`'s answer is already the failures and the path of the full log, so a `head`, `tail` or `grep` after it saves nothing and can cut a red run's failure list in half. The line is one statement — a build or test stage followed only by trimmers — and is rewritten as its first stage alone, a trailing `2>&1` dropped with the pipe it fed; a raw build is wrapped as a bare one is (``RunAdvice/inPlaceRewrite(of:)``). Any other stage after the pipe (`xcbeautify`, `tee`, `wc`, `cat`), a redirection to a file, `tail -f`, a counting, listing, quiet or recursive `grep`, a trimmer handed a file or an input redirection, a statement run in the background, or a line of several statements keeps the reading it had.
///
/// The hook applies the trim only as an amendment that adds no prompt (`InPlaceBuildRewrite.trimmed`); nothing offers it as advice, so wherever it is not applied the line is read as though it did not exist.
public struct PipedRunTrim {
    /// The line the hook runs instead.
    public let line: String

    /// The commands of ``line`` Claude Code matches its permission rules against.
    public let legs: [String]

    /// The one-line note the hook hands the model beside the rewritten line.
    public let notice: String

    /// The trim of `command`, or `nil` where it is not one build or test stage followed only by trimmers.
    public static func of(_ command: String) -> PipedRunTrim? {
        guard let (kept, dropped) = split(command) else { return nil }
        let binary = ProductName.current.binary
        let first = ShellQuery(kept)
        if first.wordsAfterBinary()?.first == "run" {
            return PipedRunTrim(line: kept, legs: [kept], notice: "\(binary): the hook dropped `\(dropped)` from this: the run's output is already the failures and a log path; full log on the `raw:` line.")
        }
        guard !first.invokesSift, let rewrite = RunAdvice.inPlaceRewrite(of: kept) else { return nil }
        return PipedRunTrim(
            line: rewrite.line,
            legs: rewrite.legs,
            notice: "\(binary): the hook rewrote this to `\(binary) run -- …` and dropped `\(dropped)`: the run's output is already the failures and a log path. Raw output: `\(kept) 2>&1 | cat`; full log on the `raw:` line."
        )
    }

    /// `command`'s first pipeline stage, trimmed and without a trailing `2>&1`, and the text after it, where `command` is one statement whose every later stage is a trimmer.
    private static func split(_ command: String) -> (kept: String, dropped: String)? {
        let statements = ShellSyntax.statementRanges(of: command)
        guard statements.count == 1, let (statement, range) = statements.first else { return nil }
        // A statement the shell is told to run in the background (`… | tail -5 &`) would run in the foreground without its pipe.
        guard ["", ";"].contains(command[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let stages = ShellSyntax.segments(of: statement)
        guard stages.count > 1 else { return nil }
        // Each stage is located in the statement in turn, so only a `|` or `|&` may stand between two: a lone `&` backgrounds a command, which no trim may drop.
        var cursor = statement.startIndex
        for (index, stage) in stages.enumerated() {
            guard let range = statement.range(of: stage, options: .literal, range: cursor ..< statement.endIndex) else { return nil }
            let gap = statement[cursor ..< range.lowerBound]
            guard index == 0 ? gap.allSatisfy(\.isWhitespace) : gap == "|" || gap == "|&" else { return nil }
            cursor = range.upperBound
        }
        guard statement[cursor...].allSatisfy(\.isWhitespace) else { return nil }
        let queries = stages.map(ShellQuery.init)
        // A group, a substitution or a backtick run in any stage puts the pipe where a cut could break the line.
        guard !queries.contains(where: { $0.executableText.contains { "(){}`".contains($0) } }),
              !queries[0].redirectsOutput,
              queries.dropFirst().allSatisfy(isTrimmer)
        else { return nil }
        var kept = stages[0].trimmingCharacters(in: .whitespaces)
        if kept.hasSuffix(" 2>&1") {
            kept = String(kept.dropLast(" 2>&1".count)).trimmingCharacters(in: .whitespaces)
        }
        let start = statement.range(of: stages[0], options: .literal).map(\.upperBound) ?? statement.endIndex
        let tail = String(statement[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = stages[0].trimmingCharacters(in: .whitespaces).hasSuffix(" 2>&1") ? "2>&1 \(tail)" : tail
        return (kept, merged)
    }

    /// Whether `stage` only cuts down what it is handed on standard input: `head`, `tail` without following, or a `grep`/`egrep`/`rg` that prints matching lines, none of them reading a file, searching a tree or writing a file.
    private static func isTrimmer(_ stage: ShellQuery) -> Bool {
        // A `<` survives here only outside quotes, so any is an input redirection, a here-document or a process substitution.
        guard let verb = stage.invocation.first.map({ ($0 as NSString).lastPathComponent }), !stage.redirectsOutput, !stage.executableText.contains("<") else { return false }
        let words = stage.invocation.dropFirst()
        return switch verb {
        case "head", "tail":
            operands(of: words, vocabulary: verb == "head" ? .head : .tail).map { $0.positionals == 0 } ?? false
        case "grep", "egrep", "rg":
            // One pattern, written bare or through `-e`/`-f`, and no operand: any word more is a file the stage would read instead of the run's output.
            operands(of: words, vocabulary: verb == "rg" ? .ripgrep : .grep).map { $0.positionals == ($0.patterns == 0 ? 1 : 0) } ?? false
        default:
            false
        }
    }

    /// How many positional words `words` hold and how many patterns its options supply, or `nil` where an option is one `vocabulary` refuses.
    ///
    /// A short cluster is read letter by letter up to the first that takes a value, digits skipped (`-qm1` is `-q -m 1`, `-5` a count, `-5c` a count and a `-c`), so a refused letter anywhere before the value refuses the stage; `grep`'s `-d`/`--directories` refuses the value `recurse`, which searches a tree. A word holding `>` is a redirection the stage already passed as writing no file (`2>&1`), and every word after `--` is positional.
    private static func operands(of words: ArraySlice<String>, vocabulary: Vocabulary) -> (positionals: Int, patterns: Int)? {
        var positionals = 0
        var patterns = 0
        var optionsEnded = false
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            index += 1
            if word.contains(">") {
                continue
            }
            guard !optionsEnded, word.hasPrefix("-"), word.count > 1 else {
                positionals += 1
                continue
            }
            if word == "--" {
                optionsEnded = true
            } else if word.hasPrefix("--") {
                let name = String(word.prefix { $0 != "=" })
                guard !vocabulary.longRefused.contains(name) else { return nil }
                patterns += vocabulary.longPatterned.contains(name) ? 1 : 0
                if vocabulary.searchesDirectories, name == "--directories" {
                    let value = word.contains("=") ? String(word.drop { $0 != "=" }.dropFirst()) : (index < words.endIndex ? words[index] : "")
                    guard value != "recurse" else { return nil }
                }
                index += vocabulary.longValued.contains(name) && !word.contains("=") ? 1 : 0
            } else {
                let letters = Array(word.dropFirst())
                for (offset, letter) in letters.enumerated() {
                    // A count digit (`-5`) ends nothing: a letter behind it (`-5c`) is still an option.
                    guard !letter.isNumber else { continue }
                    guard !vocabulary.refused.contains(letter) else { return nil }
                    guard vocabulary.valued.contains(letter) else { continue }
                    if vocabulary.searchesDirectories, letter == "d" {
                        let attached = String(letters[(offset + 1)...])
                        let value = attached.isEmpty ? (index < words.endIndex ? words[index] : "") : attached
                        guard value != "recurse" else { return nil }
                    }
                    patterns += vocabulary.patterned.contains(letter) ? 1 : 0
                    // Nothing attached after it: the value is the next word.
                    index += offset == letters.count - 1 ? 1 : 0
                    break
                }
            }
        }
        return (positionals, patterns)
    }
}

extension PipedRunTrim {
    /// The options a trimmer's words are read with: which take a value, which supply a pattern, and which make it something other than a trimmer.
    private struct Vocabulary {
        /// Short options whose value is the rest of their cluster, or the next word.
        let valued: Set<Character>

        /// Long options whose value, written without `=`, is the next word.
        let longValued: Set<String>

        /// Short options that supply a pattern.
        var patterned: Set<Character> = []

        /// Long options that supply a pattern.
        var longPatterned: Set<String> = []

        /// Short options that follow, count, list, silence or recurse.
        let refused: Set<Character>

        /// Long options that do.
        let longRefused: Set<String>

        /// Whether `-d`/`--directories` takes an action, `recurse` of which searches a tree (`grep`).
        var searchesDirectories = false

        static let head = Vocabulary(valued: ["n", "c"], longValued: ["--lines", "--bytes"], refused: [], longRefused: [])

        static let tail = Vocabulary(valued: ["n", "c", "b"], longValued: ["--lines", "--bytes"], refused: ["f", "F"], longRefused: ["--follow", "--retry"])

        static let grep = Vocabulary(
            valued: ["A", "B", "C", "D", "d", "e", "f", "m"],
            longValued: ["--regexp", "--file", "--max-count", "--after-context", "--before-context", "--context", "--label", "--binary-files", "--devices", "--directories"],
            patterned: ["e", "f"],
            longPatterned: ["--regexp", "--file"],
            refused: ["c", "l", "L", "q", "r", "R"],
            longRefused: ["--count", "--files-with-matches", "--files-without-match", "--quiet", "--silent", "--recursive", "--dereference-recursive"],
            searchesDirectories: true
        )

        static let ripgrep = Vocabulary(
            valued: ["A", "B", "C", "E", "M", "T", "d", "e", "f", "g", "j", "m", "r", "t"],
            longValued: ["--regexp", "--file", "--max-count", "--after-context", "--before-context", "--context", "--glob", "--type", "--type-not", "--replace"],
            patterned: ["e", "f"],
            longPatterned: ["--regexp", "--file"],
            refused: ["c", "l", "L", "q"],
            longRefused: ["--count", "--count-matches", "--files", "--files-with-matches", "--files-without-match", "--quiet"]
        )
    }
}
