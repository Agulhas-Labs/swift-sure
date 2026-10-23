//
// Copyright © Agulhas Labs
//

import Foundation

/// A Swift Testing ending that `xcodebuild` printed with other output spliced in between the test's name and its words, as it does when a test's own output lands on the console mid-line: `✔ Test drained() Barrierpassed after 15.5 seconds.`, or `✔ Test drained() ` followed by a whole timestamped log line from the test process, with `passed after 198.5 seconds.` alone on the next line.
///
/// **The line still opens on the framework's own head**, a status glyph and `Test ` and the name, which is what every reader anchors on, so this is not ``RunGluedTestLine``'s case of a framework line found mid-line: nothing is searched for. What it reads is narrower than the words after the name. Those words are spliced output only where they do not open on a lowercase word, as every wording Swift Testing prints after a name does (`started`, `passed after`, `recorded an issue`, `was cancelled after`), so an issue line whose message quotes `passed after 1 seconds.` is never taken for an ending, and a wording this reader has never seen stays one it cannot read. The ending is taken only where it closes the line whole, or is the whole of the next line, and ``RunTestOutcomes`` takes it only for a test whose start is still waiting for an ending.
///
/// **Where both hold, the next line wins.** Spliced output can close on an ending's wording of its own (a log line saying a subtask `passed after 3 seconds.`), so a line closing on one is still held for the next line, and an ending that is the whole of that line is the framework's: it replaces the one read from the closing words. Only where the next line is no ending do the closing words stand. Nor do closing words count after an issue recorded, spliced or not: an issue's message may quote an ending, and the test's own ending is still to come, so the line is held as a head with none.
///
/// **A head's glyph rules out a plain pass.** Swift Testing prints `✘` in front of a failure or an issue and never in front of a pass, which has a glyph of its own even where it carries known issues (`━`), so the words `passed after 2 seconds.` after a `✘` head are spliced output, on the line itself or the next one, and never its ending.
struct RunSplicedTestEnding {
    /// What `line`'s words after its test's name are, or `nil` for a line that is no Swift Testing line about one test.
    static func reading(of line: String) -> Reading? {
        guard let (name, tail) = RunTestOutcomes.swiftTestingLine(in: line) else {
            return nil
        }
        var words = tail
        if words.hasPrefix(" with "), let cases = words.prefixMatch(of: #/ with \d+ test cases?/#) {
            words = words[cases.range.upperBound...]
        }
        guard words.isEmpty || words.hasPrefix(" "), words.dropFirst().first?.isLowercase != true else {
            return .unknownWords
        }
        let undecorated = RunOutputFilter.undecorated(line)
        let head = String(line[..<undecorated.startIndex]) + "Test " + name + String(tail[..<words.startIndex])
        guard !words.contains(issueWording), let spliced = words.wholeMatch(of: splicedEnding), !contradicts(head, spliced.output.1) else {
            return .spliced(head: head, ending: nil)
        }
        return .spliced(head: head, ending: head + " " + String(spliced.output.1))
    }

    /// The ending `head` was waiting for, as the framework would have printed it on one line, where `line` is the whole of an ending's words; `nil` otherwise.
    static func completed(_ head: String, by line: String) -> String? {
        line.wholeMatch(of: ending) == nil || contradicts(head, line[...]) ? nil : head + " " + line
    }

    /// What `line`, the one after `held`, makes of it: the ending to read in the held line's place where `line` completes it, and the test whose ending was read from the held line's closing words where `line` shows they were not its ending.
    ///
    /// They were not where `line` is the framework's ending, and not where it opens on an issue's words either: the held line was then an issue's head, and its closing words the spliced output's, whatever they say.
    static func settled(_ held: Held, by line: String) -> Settled {
        if let ending = completed(held.head, by: line) {
            return Settled(retracted: held.endedTest, ending: ending)
        }
        return Settled(retracted: line.prefixMatch(of: issueWording) == nil ? nil : held.endedTest, ending: nil)
    }

    /// Whether `head` opens on the failure glyph and `words` are a plain pass's, which the framework never prints together.
    private static func contradicts(_ head: String, _ words: Substring) -> Bool {
        words.wholeMatch(of: plainPass) != nil && head[..<RunOutputFilter.undecorated(head).startIndex].contains(failureGlyph)
    }

    /// The glyph Swift Testing prints in front of a failure or an issue, and never in front of a pass.
    private static var failureGlyph: Character {
        "✘"
    }

    /// A pass's words with no known issue, whole.
    private static var plainPass: Regex<Substring> {
        #/passed after [\d.]+ seconds?\./#
    }

    /// An ending's words, whole: `passed after 0.001 seconds.`, `… with 1 known issue.`, `failed after 0.001 seconds with 2 issues (including 1 known issue).`.
    private static var ending: Regex<Substring> {
        #/(?:passed after [\d.]+ seconds?(?: with \d+ known issues?)?|failed after [\d.]+ seconds? with \d+ issues?(?: \(including \d+ known issues?\))?)\./#
    }

    /// The words Swift Testing prints after a name for an issue, known or not, which an ending's wording later in the line never makes an ending.
    private static var issueWording: Regex<Substring> {
        #/recorded an? (?:known )?issue/#
    }

    /// The words after a name where spliced output stands between the name and an ending that closes the line, the ending captured.
    private static var splicedEnding: Regex<(Substring, Substring)> {
        #/ .+?((?:passed after [\d.]+ seconds?(?: with \d+ known issues?)?|failed after [\d.]+ seconds? with \d+ issues?(?: \(including \d+ known issues?\))?)\.)/#
    }
}

extension RunSplicedTestEnding {
    /// What the words after a Swift Testing line's test name are, for a line that is neither the test's start nor an ending the reader knows.
    enum Reading: Equatable {
        /// Words this reader cannot read, which may be the framework's: an issue, or an ending worded in a way the reader has never seen.
        ///
        /// Every word opening on a lowercase letter is read this way, and so is a display name with no space after its closing quote.
        case unknownWords
        /// Other output spliced in after the name; `head` is the line's glyph, `Test ` and name to complete with the next line, and `ending` the line as the framework printed it where its ending closes this one.
        case spliced(head: String, ending: String?)
    }

    /// What the line after a held line settles about it.
    struct Settled: Equatable {
        /// The test whose ending, read from the held line's closing words, is to be taken back; `nil` where it stands or none was read.
        var retracted: String?
        /// The held line completed into the ending the framework printed, to read in its place; `nil` where the line is no ending of its.
        var ending: String?
    }

    /// A started test's spliced line, held for exactly one line in case that line is the whole of the test's ending.
    struct Held: Sendable, Equatable {
        /// The line's glyph, `Test ` and name, to complete with the next line.
        var head: String
        /// The test whose ending the line's closing words were already read as, which an ending on the next line replaces; `nil` where they were none.
        var endedTest: String?
    }
}
