//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// The one line the post-tool hook adds after a piped build or test whose output shows a failure, naming the `swift-sure run` call that would have listed it.
///
/// The pre-tool hook lets `swift build 2>&1 | tail -3` through as written, since a rewrite would drop the pipe's filter and change its exit status. So the answer comes after the call ran, and only when the output shows a failure: a failure verdict, or a located diagnostic where the command's own success verdict is not in the output. The rule is Docs/Design.md's "A piped build that fails is named after it ran".
public struct PipedBuildFailure {
    /// The note for the `command` a `Bash` or `Shell` call ran and the `output` it printed, or `nil` where the call is not one piped build, its output shows no failure or `deadline` passes before the output is read.
    public static func note(for command: String, output: String, deadline: Date = .distantFuture) -> String? {
        guard let build = Build(command), shows(output, failureOf: build.invocation, deadline: deadline),
              let line = RunAdvice.inPlaceRewrite(of: build.line).map({ build.restoringOpeners(in: $0.line) })
        else {
            return nil
        }
        let label = RunCommandKind.executesTests(build.invocation) ? "test run" : "build"
        return "\(ProductName.current.binary): this piped \(label) failed. `\(line)` lists each failure once by signature and keeps the full log under \(ProductName.current.directoryName)/runs/."
    }

    /// The literals a line must hold to be a verdict or a located diagnostic at all, tried before any pattern: nearly every line of a long log holds none of them.
    private static let markers = [
        "FAILED", "SUCCEEDED", "INTERRUPTED", "Build complete!", "Test run with ", "Test Suite '", "Note: Some test targets",
        "exited with unexpected signal", "error: ", "Executed ", " recorded an issue ", " failed after ",
    ]

    /// How many lines are read between looks at the clock.
    private static let linesPerClockLook = 512

    /// Whether `output` shows a failure of the build `invocation` ran: any failure verdict, or, with no success verdict that command owes, a located diagnostic.
    ///
    /// `false` once `deadline` passes.
    private static func shows(_ output: String, failureOf invocation: [String], deadline: Date) -> Bool {
        let owed = RunVerdict.Contract.of(invocation)
        var succeeded = false
        var located = false
        for (index, raw) in output.split(whereSeparator: \.isNewline).enumerated() {
            if index.isMultiple(of: linesPerClockLook), deadline.timeIntervalSinceNow <= 0 {
                return false
            }
            let plain = raw.utf8.contains(0x1B) ? Substring(RunOutputFilter.strippedOfANSIEscapes(String(raw))) : raw
            guard markers.contains(where: { plain.contains($0) }) else { continue }
            let line = String(plain).trimmingCharacters(in: .whitespaces)
            if isAFailureVerdict(line) || isAPerTestFailureLine(String(plain)) {
                return true
            }
            switch owed {
            case .runTally: succeeded = succeeded || isASwiftTestingPass(line)
            case let .some(contract): succeeded = succeeded || (contract.line(for: .succeeded).map { line.hasPrefix($0) } ?? false)
            case nil: break
            }
            located = located || isALocatedDiagnostic(line)
        }
        return !succeeded && located
    }

    /// A line that declares the run failed: a `** … FAILED **` banner or SwiftPM's closing lines, a counter or suite line of XCTest, a Swift Testing run line, or a test process that died on a signal.
    private static func isAFailureVerdict(_ line: String) -> Bool {
        if RunVerdict.state(of: line) == .failed || line.hasPrefix("Note: Some test targets reported failures:") {
            return true
        }
        if line.hasPrefix("Test Suite '"), line.contains("' failed") {
            return true
        }
        if line.hasPrefix("Executed "), let counted = line.firstMatch(of: #/^Executed \d+ tests?, with (\d+) failures?/#), Int(counted.1) ?? 0 > 0 {
            return true
        }
        if RunOutputFilter.undecorated(line).hasPrefix("Test run with "), RunOutputFilter.undecorated(line).contains(" failed") {
            return true
        }
        if let start = line.range(of: "error: Process '"), line[start.upperBound...].contains("exited with unexpected signal code") {
            return true
        }
        return false
    }

    /// Swift Testing's report that one test failed, read only where `line` opens with the framework's own glyph.
    ///
    /// Not indented and not behind a `+` or `-`: text a commit message or a diff prints would otherwise be read as the build's.
    private static func isAPerTestFailureLine(_ line: String) -> Bool {
        guard let first = line.first, !first.isASCII, !first.isWhitespace else { return false }
        return RunTestOutcomes.isASwiftTestingFailure(line)
    }

    /// `<path>:<line>[:<col>]: error:` anywhere in the line: a compiler error or an XCTest assertion.
    private static func isALocatedDiagnostic(_ line: String) -> Bool {
        line.contains(": error:") && line.contains(#/:\d+(:\d+)?: error:/#)
    }

    /// A Swift Testing tally that ran at least one test and passed, the verdict `swift test` owes.
    private static func isASwiftTestingPass(_ line: String) -> Bool {
        let undecorated = RunOutputFilter.undecorated(line)
        guard undecorated.hasPrefix("Test run with "), undecorated.contains(" passed"),
              let count = undecorated.dropFirst("Test run with ".count).split(separator: " ").first.flatMap({ Int($0) })
        else {
            return false
        }
        return count > 0
    }
}

private extension PipedBuildFailure {
    /// The one pipeline a call's line holds, cut back to its build stage.
    private struct Build {
        /// The build's argv, for the label and the success verdict it owes.
        let invocation: [String]
        /// The call's line up to and including the build stage, without its redirections or the parentheses opening a subshell at the build, and with the closers of any group the pipeline ended.
        let line: String
        /// The text in front of the build stage, which the rewrite leaves as it is.
        private let before: String
        /// The parentheses that opened a subshell at the build itself: the rewrite reads a statement from its command word, so they are held out of ``line`` and put back by ``restoringOpeners(in:)``.
        private let openers: String

        /// `rewritten`, the rewrite of ``line``, with the build's own subshell openers put back in front of the build.
        func restoringOpeners(in rewritten: String) -> String {
            guard !openers.isEmpty, rewritten.hasPrefix(before) else { return rewritten }
            return before + openers + rewritten.dropFirst(before.count)
        }

        init?(_ command: String) {
            let all = ShellSyntax.segments(of: command).map(ShellQuery.init)
            guard !all.contains(where: { $0.invokesSift || $0.suppliesInlineText }) else { return nil }
            var pipeline: (stages: [ShellQuery], range: Range<String.Index>)?
            var directoryText = ""
            var skippedBefore = false
            let statements = ShellSyntax.statementRanges(of: command)
            for (index, (statement, range)) in statements.enumerated() {
                let stages = ShellSyntax.segments(of: statement).map(ShellQuery.init)
                if stages.count == 1, ["cd", "set"].contains(stages[0].invocation.first ?? "") {
                    if pipeline == nil {
                        let end = index + 1 < statements.count ? statements[index + 1].range.lowerBound : range.upperBound
                        let text = command[range.lowerBound ..< end]
                        directoryText += directoryText.isEmpty ? String(text.drop { $0.isWhitespace }) : String(text)
                    }
                    continue
                }
                if stages.count > 1, let first = stages.first, Self.isFilteredBuild(first) {
                    guard pipeline == nil else { return nil }
                    pipeline = (stages, range)
                } else if Self.isHarmless(stages) {
                    skippedBefore = skippedBefore || pipeline == nil
                } else {
                    return nil
                }
            }
            guard let (stages, range) = pipeline, stages.count > 1, let build = stages.first,
                  RunCommandKind.recognize(build.invocation).isFiltered, RunCommandKind.recognize(build.invocation) != .linter,
                  !stages.dropFirst().contains(where: { $0.invocation.count == 1 && ($0.invocation[0] as NSString).lastPathComponent == "cat" }),
                  !RunAdvice.servesTheVerdictWholesale(build.invocation, onASplitGateLine: false), !build.writesOutputToAFile,
                  let stage = command.range(of: build.segment, options: .literal, range: range),
                  build.executableText.count == build.segment.count
            else {
                return nil
            }
            let kept = Self.withoutRedirections(build)
            let blanks = kept.prefix { $0.isWhitespace }
            let opening = kept.dropFirst(blanks.count).prefix { $0 == "(" }
            let leading = skippedBefore ? directoryText + command[range.lowerBound ..< stage.lowerBound] : command[..<stage.lowerBound]
            let prefix = skippedBefore && directoryText.isEmpty ? "" : String(leading) + blanks
            let open = Self.depth(of: prefix) + opening.count
            let trailing = stages.last?.segment.trimmingCharacters(in: .whitespaces).reversed().prefix { $0 == ")" }.count ?? 0
            invocation = build.invocation
            before = prefix
            openers = String(opening)
            line = prefix + kept.dropFirst(blanks.count + opening.count) + String(repeating: ")", count: min(open, trailing))
        }

        /// `stage` without its redirections, each an operator and its target (`2>&1`, `> log`, `2>/dev/null`, `&>log`), and with every other word kept in order, so arguments written after a redirection survive.
        private static func withoutRedirections(_ stage: ShellQuery) -> String {
            let written = Array(stage.segment)
            let blanked = Array(stage.executableText)
            var words: [Range<Int>] = []
            var start: Int?
            var quote: Character?
            var escaped = false
            for (index, character) in written.enumerated() {
                if start == nil {
                    guard !character.isWhitespace else { continue }
                    start = index
                }
                if escaped {
                    escaped = false
                } else if character == "\\", quote != "'" {
                    escaped = true
                } else if let open = quote {
                    quote = character == open ? nil : open
                } else if character == "'" || character == "\"" {
                    quote = character
                } else if character.isWhitespace, let begun = start {
                    words.append(begun ..< index)
                    start = nil
                }
            }
            if let begun = start {
                words.append(begun ..< written.count)
            }
            var result = ""
            var previousEnd = 0
            var targetFollows = false
            for word in words {
                defer { previousEnd = word.upperBound }
                if targetFollows {
                    targetFollows = false
                    continue
                }
                let text = String(blanked[word])
                if let operatorOnly = redirection(in: text) {
                    targetFollows = operatorOnly
                    continue
                }
                result += String(written[previousEnd ..< word.lowerBound]) + String(written[word])
            }
            return result
        }

        /// Whether `word` is a redirection: `nil` where it is not, `true` where it is an operator whose target is the next word, `false` where the target is attached.
        private static func redirection(in word: String) -> Bool? {
            guard let found = word.firstMatch(of: #/^(?:\d+|&)?(?:>>?|<)(.*)$/#) else { return nil }
            return found.1.isEmpty
        }

        /// Whether `stage` runs a build or test the post-run note can name: recognised as one that is filtered, and not a linter.
        private static func isFilteredBuild(_ stage: ShellQuery) -> Bool {
            let kind = RunCommandKind.recognize(stage.invocation)
            return kind.isFiltered && kind != .linter
        }

        /// Whether a statement beside the build runs no build and prints nothing a build verdict could be read from: `true`, `pwd`, `date`, `git stash` with a changing subcommand, or `git status` in a short form.
        private static func isHarmless(_ stages: [ShellQuery]) -> Bool {
            guard let first = stages.first?.invocation, let command = first.first,
                  stages.allSatisfy({ RunCommandKind.recognize($0.invocation) == .unrecognized })
            else {
                return false
            }
            let arguments = Array(first.dropFirst())
            switch command {
            case "true", "pwd", "date":
                return true
            case "git":
                guard let subcommand = arguments.first else { return false }
                let rest = Array(arguments.dropFirst())
                switch subcommand {
                case "stash":
                    let quiet: Set = ["-q", "--quiet"]
                    let verbs: Set = ["push", "pop", "apply", "drop", "save", "clear"]
                    guard let verb = rest.first else { return true }
                    if quiet.contains(verb) {
                        return rest.count == 1
                    }
                    return verbs.contains(verb) && rest.dropFirst().allSatisfy { quiet.contains($0) }
                case "status":
                    let forms: Set = ["-s", "--short", "--porcelain", "-b", "--branch", "-q"]
                    return rest.allSatisfy { forms.contains($0) }
                default:
                    return false
                }
            default:
                return false
            }
        }

        /// How many parentheses `text` opens that it does not close.
        private static func depth(of text: String) -> Int {
            ShellSyntax.executableText(of: text).reduce(0) { $1 == "(" ? $0 + 1 : $1 == ")" ? max($0 - 1, 0) : $0 }
        }
    }
}
