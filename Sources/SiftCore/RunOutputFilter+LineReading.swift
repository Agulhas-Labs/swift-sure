//
// Copyright © Agulhas Labs
//

import Foundation

/// The pure readers of a failure line: the test name in a head, the split of an issue tail, and the continuation shapes of a note.
extension RunOutputFilter {
    /// The test's name from the part of the line before the marker, or `nil` when the line names a suite rather than a test.
    ///
    /// **The word `Test` is read where the framework writes it — first, immediately after the decoration — and never searched for backwards.** A backwards search takes the *last* ` Test ` in the head, which is the author's word rather than Swift Testing's the moment a display name contains one: `Suite "Reflow Test Grid" failed after …` would be read as a test called `Grid"`, get a failure invented for it in ``appendUnexplainedFailures()`` against a run whose own tally said two issues, and have that name filed into `run.jsonl` and from there into `flakes` — a test that does not exist, recorded as having failed. `Test "The Test Reads Its Own Name" recorded an issue …` is the milder half of the same fault, and would report as `Reads Its Own Name"`.
    ///
    /// A backwards search is what surviving `xcodebuild` splicing one runner's line through the middle of another's would call for, and the captured red run does not support it: `Test .* Test ` occurs zero times in 8,185 lines. What splicing actually looks like there is ``RunOutputFilter/outputBarrier`` on the head of a line, which ``consume(line:)`` takes off before this is reached — so that case arrives here already repaired, and the failure a backwards search causes in exchange is ordinary Swift Testing. The display name is what the reading is sized against.
    ///
    /// **Decoration is dropped by category rather than by enumerating glyphs.** Every one of these lines opens with a status glyph and whitespace, and which glyph depends on the terminal Swift Testing thinks it is writing to — `✘` in the `xcodebuild` captures, a private-use SF Symbol under `swift test` — with a zero-width space in front of it on some lines and not others in the same run. None of them is a letter or a digit, and the word that follows always is, so a run of neither is exactly the decoration.
    ///
    /// The suite check lives here with it. A suite line is one whose first word is `Suite`, which is a fact about the head; testing the *name* for it works only while nothing can stand between the two. XCTest's `Test Suite 'X'` is a third shape that reaches this and still has to be turned away, which is what the remaining prefix guards are for.
    func testName(inHead head: String) -> String? {
        let undecorated = Self.undecorated(head)
        guard undecorated.hasPrefix("Test ") else {
            return nil
        }
        let name = undecorated.dropFirst("Test ".count).trimmingCharacters(in: .whitespaces)
        // `case ` is Swift Testing's own parameterized-case event, `Test case passing 1 argument … started.`,
        // whose argument can quote a whole failure line: never a test's name.
        guard !name.isEmpty, !name.hasPrefix("Case "), !name.hasPrefix("case "), !name.hasPrefix("Suite ") else {
            return nil
        }
        // `Test everyDoorSurvivesEveryTextSize(size:) with 3 test cases failed after …` — the clause sits
        // between the name and the marker, so taking everything in front of the marker as the name would
        // file one function under two names depending on which line reported it. It is a count of the
        // cases the framework ran, not part of what the function is called.
        return RunTestOutcomes.droppingAlias(name.replacing(#/ with \d+ test cases?$/#, with: ""))
    }

    /// Splits what follows `recorded an issue` into the arguments the case carried, if any, and the `File.swift:10:9: …` after them.
    ///
    /// Two shapes, both real: `at File.swift:10:9: …` from a plain test, and `with 1 argument size → .large at File.swift:312:13: …` from a parameterized one. `nil` for anything else, which leaves the line to the readers after this one rather than to a guess.
    ///
    /// The boundary in the second shape is the ` at ` that a `File.swift:10:9:` token follows — not the first in the line and not the last. An argument's printed value can contain the word and so can the message after it, and only the shape of what comes next tells the three apart.
    func splitIssueTail(_ tail: String) -> (arguments: String?, located: String)? {
        if tail.hasPrefix("at ") {
            return (nil, String(tail.dropFirst(3)))
        }
        guard let head = tail.prefixMatch(of: Self.argumentsHead) else {
            return nil
        }
        let arguments = tail[head.range.upperBound...]
        guard let boundary = Self.locationBoundary(in: arguments) else {
            return nil
        }
        return (String(arguments[..<boundary.lowerBound]), String(arguments[boundary.upperBound...]))
    }

    /// The ` at ` that separates a failure's arguments from where it failed.
    static func locationBoundary(in text: Substring) -> Range<Substring.Index>? {
        var searchFrom = text.startIndex
        while let candidate = text.range(of: " at ", range: searchFrom ..< text.endIndex) {
            // Bounded by the first whitespace, so a message with no location in it costs one token's
            // worth of looking per candidate rather than a scan to the end of a kilobyte-long line.
            let token = text[candidate.upperBound...].prefix { !$0.isWhitespace }
            if token.wholeMatch(of: /\S+:\d+:\d+:/) != nil {
                return candidate
            }
            searchFrom = candidate.upperBound
        }
        return nil
    }

    /// Splits `File.swift:10:9: Expectation failed: …` into its location and its message.
    func splitLocation(_ tail: String) -> (String?, String) {
        guard let separator = tail.range(of: ": ") else {
            return (nil, tail)
        }
        return (String(tail[tail.startIndex ..< separator.lowerBound]), String(tail[separator.upperBound...]))
    }

    /// The text of a `↳` continuation line, or `nil` when the line is not one.
    ///
    /// A bare `↳` is one, with empty text: Swift Testing prints a comment whose first line is blank that way, and the comment's lines follow it indented, so reading it as the note's end left the comment and every value beneath it out of the answer. Its empty text is held as a blank inside a note is (``foldNoteLine(_:marked:into:indent:)``).
    ///
    /// The marker is searched for rather than anchored on the start of the line: 306 lines of the captured logs carry a zero-width space (U+200B) in front of their glyph, and `CharacterSet.whitespaces` does not contain it, so a prefix test on the raw line is exactly the reader that misses them.
    func markedContinuation(in line: String) -> String? {
        guard let marker = line.firstIndex(of: "↳") else {
            return nil
        }
        guard line[line.startIndex ..< marker].allSatisfy({ $0.isWhitespace || $0 == "\u{200B}" }) else {
            return nil
        }
        return line[line.index(after: marker)...].trimmingCharacters(in: .whitespaces)
    }

    /// The text of a continuation line that carries no `↳` of its own, or `nil` when the line is not indented at all.
    ///
    /// **A merely-indented line is a continuation too, on the same terms as an error's colon-continuation (``appendColonContinuation(_:)``).** A `↳` comment can itself end on a colon and open a list the next, unmarked, indented line answers: `Expectation failed: wrong.isEmpty` / `↳ 1 citation(s) name a line their rule is not on: (by adjacency)` / an indented line naming the actual citation is three lines, and a reader who sees only the first two is missing the sentence the comment was written to introduce. Consulted only while a failure's note is open, which a real summary or outcome line never arrives inside (see ``recordQuotedLine(_:on:)``), so an indented one — XCTest's `\t Executed …` counter — is never mistaken for one of these.
    ///
    /// **Genuine whitespace only — never the zero-width space (U+200B) some of Swift Testing's own decorated lines open on.** ``markedContinuation(in:)`` skips past a leading U+200B because it is looking for the `↳` glyph behind it, but a status line like `◇ Suite BinLabelTests started.` can carry the same leading U+200B in front of its own glyph and nothing that follows is a continuation of anything — reading `isWhitespace` alone (which U+200B is not) is what keeps a decorated status line, of all things, from being folded into the failure printed above it.
    func plainContinuation(in line: String) -> String? {
        guard let first = line.first, first.isWhitespace else {
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The text of a continuation in the shape Swift Testing prints a comment's later lines in — opening on a space — or `nil` for any other line, a tab-indented one included.
    ///
    /// Swift Testing puts two spaces in front of every line of a multi-line comment after the first, whatever the line itself opens on, so a quoted `Executed …` counter arrives as `    Executed …`. XCTest's own counter opens on a tab.
    func quotedContinuation(in line: String) -> String? {
        line.first == " " ? plainContinuation(in: line) : nil
    }

    /// Whether `line` is the indented nothing Swift Testing prints for an empty line inside a note — whitespace, and some of it; a line with nothing at all on it is left to end the note, as it always has.
    static func isBlank(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy(\.isWhitespace)
    }

    /// The `with 1 argument ` that opens a parameterized failure's arguments.
    static var argumentsHead: Regex<Substring> {
        #/with \d+ arguments? /#
    }
}

/// A parameterized failure's name and its arguments so far, while `continueOpenIssue(_:)` waits for the line naming its location.
struct RunOpenIssue {
    let name: String
    var arguments: String
    var lines = 1
}
