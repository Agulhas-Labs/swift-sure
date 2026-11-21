//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A bare `↳` is the first line of a comment that opens on a blank line, and the note carries on across it rather than ending there.
struct RunBareMarkerNoteTests {
    /// The comment's lines and the values beneath it stay the failure's: before, the note ended at the bare marker and the failure printed its message alone.
    @Test
    func aCommentOpeningOnABlankLineKeepsItsLinesAndTheExpansionBeneathIt() throws {
        let failure = try #require(Self.report([
            "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: flag",
            "↳ ",
            "  alpha",
            "  beta",
            "↳ flag → false",
        ]).testFailures.first)

        #expect(failure.note == "alpha\nbeta flag → false")
        #expect(failure.markedLines == ["flag → false"])
    }

    /// A containment haystack whose first line is blank, repeated by the comment, compacts as any other: the comment is dropped and the clause says so.
    @Test
    func aBlankFirstLineCommentRepeatingTheHaystackIsDropped() throws {
        let failure = try Self.containment(value: ["", "second line", "third line"], comment: ["", "second line", "third line"])

        #expect(failure.note == "output.contains(\"x\") → false output → \"\nsecond line (line 2 of 3 lines; the comment repeats them — see the raw log)")
        #expect(failure.closestLine == "no line shares text with it")
    }
}

private extension RunBareMarkerNoteTests {
    static func report(_ lines: [String]) -> RunReport {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in lines {
            filter.consume(line: line)
        }
        return filter.finish()
    }

    /// The one failure of `output.contains("x")` with `value` as the receiver's lines and `comment` above the expansions, a blank first line of either printed as Swift Testing prints it.
    static func containment(value: [String], comment: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> RunTestFailure {
        var lines = ["✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")", "↳ \(comment[0])"]
        lines += comment.dropFirst().map { "  \($0)" }
        lines.append("↳ output.contains(\"x\") → false")
        lines.append("↳   output → \"\(value[0])")
        for (offset, line) in value.dropFirst().enumerated() {
            lines.append("    \(line)\(offset == value.count - 2 ? "\"" : "")")
        }
        return try #require(report(lines).testFailures.first, sourceLocation: sourceLocation)
    }
}
