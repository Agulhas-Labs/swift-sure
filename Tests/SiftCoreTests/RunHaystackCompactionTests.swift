//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A failed `contains` over a multi-line answer string says the answer in one line: the receiver's `↳` line and a count, with a comment that repeats it dropped, because the closest line already names the line that matters.
struct RunHaystackCompactionTests {
    /// The three failures a package whose answer string is twelve lines printed, each as the console logged it: a comment repeating the answer, the expansions, the value.
    @Test
    func threeContainmentFailuresOverTheSameAnswerPrintTwoLinesEach() {
        let report = Self.report(Self.probeLog)
        let containment = report.testFailures.filter { $0.name != "plainOperand()" }
        let rendered = RunFailureShape.of(Self.shapeFailures(containment), changedFiles: .of([])).rendered()
        let clause = "(first of 12 lines; the comment repeats them — see the raw log)"
        let expected = [
            "  containsFolded() — GizmoTests.swift:6:5",
            "    Expectation failed: output.contains(\"folded in here\") → false output → \"line 1 of the answer: widget 7 \(clause)",
            "    no line shares text with it",
            "  secondTest() — GizmoTests.swift:12:5",
            "    Expectation failed: output.contains(\"other note\") → false output → \"line 1 of the answer: widget 7 \(clause)",
            "    no line shares text with it",
            "  containsFolded() — GizmoTests.swift:7:5",
            "    Expectation failed: !output.contains(\"widget 14\") → true output.contains(\"widget 14\") → false output → \"line 1 of the answer: widget 7 \(clause)",
            "    closest line: line 2 of the answer: widget 14",
        ]
        for line in expected {
            #expect(rendered.contains(line), "\(line)\n---\n\(rendered.joined(separator: "\n"))")
        }

        #expect(!rendered.contains { $0.contains("widget 21") })
    }

    /// An equality is not a containment failure: the value is the answer, so its note prints as it always did.
    @Test
    func anEqualityOverTheSameAnswerPrintsAsBefore() throws {
        let failure = try #require(Self.report(Self.probeLog).testFailures.first { $0.name == "plainOperand()" })

        #expect(failure.note?.hasPrefix("output == \"short\" → false output → \"line 1 of the answer: widget 7\nline 2") == true)
        #expect(failure.note?.hasSuffix("\n… (+1 more lines — see the raw log)") == true)
        #expect(failure.note?.contains("of 12 lines") == false)
    }

    @Test
    func aBlankFirstLineSaysTheFirstNonBlankLineAndItsPosition() throws {
        let failure = try Self.containment(value: ["", "second line", "third line"], comment: nil)

        #expect(failure.note == "output.contains(\"x\") → false output → \"\nsecond line (line 2 of 3 lines — see the raw log)")
    }

    @Test
    func aCommentDifferingByOneCharacterIsKeptAndTheClauseDoesNotClaimIt() throws {
        let failure = try Self.containment(value: ["one", "two", "three"], comment: ["one", "two", "thre3"])

        #expect(failure.note == "one\ntwo\nthre3 output.contains(\"x\") → false output → \"one (first of 3 lines — see the raw log)")
    }

    @Test
    func aCommentRepeatingTheValueIsDroppedFromTheNote() throws {
        let failure = try Self.containment(value: ["one", "two", "three"], comment: ["one", "two", "three"])

        #expect(failure.note == "output.contains(\"x\") → false output → \"one (first of 3 lines; the comment repeats them — see the raw log)")
        #expect(failure.markedLines.count == 3)
    }

    @Test
    func aValueThatNeverClosesItsQuoteIsPrintedAsBefore() throws {
        var filter = RunOutputFilter(expecting: .runTally)
        filter.consume(line: "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")")
        filter.consume(line: "↳ output.contains(\"x\") → false")
        filter.consume(line: "↳   output → \"one")
        filter.consume(line: "    two")
        filter.consume(line: "    three")
        let failure = try #require(filter.finish().testFailures.first)

        #expect(failure.note == "output.contains(\"x\") → false output → \"one\ntwo\nthree")
    }

    @Test
    func aValueCutOffByTheNoteLimitIsPrintedAsBefore() throws {
        let rows = RunFailureCensus.closestLineNoteLimit.lines + 5
        var filter = RunOutputFilter(expecting: .runTally)
        filter.consume(line: "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")")
        filter.consume(line: "↳ output.contains(\"x\") → false")
        filter.consume(line: "↳   output → \"row 0")
        for row in 1 ..< rows {
            filter.consume(line: "    row \(row)\(row == rows - 1 ? "\"" : "")")
        }
        let failure = try #require(filter.finish().testFailures.first)

        #expect(failure.note?.contains("see the raw log)") == true)
        #expect(failure.note?.contains("first of") == false)
        #expect(failure.note?.contains("row 5") == true)
    }

    /// An expectation that is no containment call keeps its list: the offenders are the answer.
    @Test
    func aNonContainmentNoteIsUntouched() {
        var filter = RunOutputFilter(expecting: .runTally)
        filter.consume(line: "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: report.isEmpty")
        filter.consume(line: "↳ 2 offenders:")
        filter.consume(line: "  Gizmo.swift:1  first")
        filter.consume(line: "  Gizmo.swift:2  second")
        let report = filter.finish()

        #expect(report.testFailures.first?.note == "2 offenders:\nGizmo.swift:1  first\nGizmo.swift:2  second")
    }

    /// The twelve-line cap counts what is left after compaction, and the elision counts only those lines.
    @Test
    func theCapAndItsCountApplyToTheCompactedNote() throws {
        let extra = (1 ... 14).map { "detail \($0)" }
        var filter = RunOutputFilter(expecting: .runTally)
        filter.consume(line: "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")")
        filter.consume(line: "↳ \(extra[0])")
        for line in extra.dropFirst() {
            filter.consume(line: "  \(line)")
        }
        filter.consume(line: "↳ output → \"one")
        filter.consume(line: "    two")
        filter.consume(line: "    three\"")
        let failure = try #require(filter.finish().testFailures.first)
        let lines = try #require(failure.note?.components(separatedBy: "\n"))

        // 14 comment lines, the haystack line, and the clause: 12 kept, 3 elided.
        #expect(lines.count == 13)
        #expect(lines.last == "… (+3 more lines — see the raw log)")
        #expect(lines.contains { $0.contains("first of 3 lines") } == false)
    }

    /// A first line too long for the note-line cap is clipped inside the line, so the clause the renderer prints is whole.
    @Test
    func aLongFirstLineIsClippedBeforeItsClauseAndTheClauseSurvivesTheRenderer() throws {
        let long = String(repeating: "a", count: 1100)
        let rendered = try Self.rendered(Self.containment(value: [long, "line 2", "line 3"], comment: nil))

        #expect(rendered.contains("the first clipped — see the raw log)"), "\(rendered)")
        #expect(rendered.contains("of 3 lines"), "\(rendered)")
        #expect(!rendered.contains("characters — see the raw log"), "\(rendered)")
    }

    @Test
    func aLongFirstLineKeepsTheCommentClauseWhenTheCommentRepeatsIt() throws {
        let long = "x" + String(repeating: "a", count: 249)
        let rendered = try Self.rendered(Self.containment(value: [long, "line 2", "line 3"], comment: [long, "line 2", "line 3"]))

        #expect(rendered.contains("(first of 3 lines, the first clipped; the comment repeats them — see the raw log)"), "\(rendered)")
        #expect(!rendered.contains("characters — see the raw log"), "\(rendered)")
    }

    /// A kept comment's last line and the expansions share one printed line with the haystack's, so the haystack is clipped to what that line leaves.
    @Test
    func aLongFirstLineAfterAKeptCommentKeepsItsClauseOnTheSharedLine() throws {
        let long = String(repeating: "a", count: 250)
        let rendered = try Self.rendered(Self.containment(value: [long, "line 2", "line 3"], comment: ["x" + long, "line 2", "line 3"]))
        let lines = rendered.split(separator: "\n")

        #expect(lines.contains { $0.hasSuffix("(first of 3 lines, the first clipped — see the raw log)") }, "\(rendered)")
        #expect(!lines.contains { $0.hasSuffix("characters — see the raw log)") && $0.contains("output → ") }, "\(rendered)")
    }

    @Test
    func aLongFirstNonBlankLineIsClippedOnItsOwnLineWithItsClause() throws {
        let long = String(repeating: "b", count: 300)
        let rendered = try Self.rendered(Self.containment(value: ["", long, "line 3"], comment: nil))

        #expect(rendered.contains("… (line 2 of 3 lines, clipped — see the raw log)"), "\(rendered)")
        #expect(!rendered.contains("characters — see the raw log"), "\(rendered)")
    }

    /// A later value that runs past the note limit makes the whole note a cut-off one, which is printed as before even though the haystack closed.
    @Test
    func aLaterValueCutOffByTheNoteLimitLeavesAClosedHaystackPrintedAsBefore() throws {
        let rows = RunFailureCensus.closestLineNoteLimit.lines + 5
        var filter = RunOutputFilter(expecting: .runTally)
        filter.consume(line: "✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")")
        filter.consume(line: "↳ output.contains(\"x\") → false")
        filter.consume(line: "↳   output → \"one")
        filter.consume(line: "    two")
        filter.consume(line: "    three\"")
        filter.consume(line: "↳   needle → \"row 0")
        for row in 1 ..< rows {
            filter.consume(line: "    row \(row)")
        }
        let failure = try #require(filter.finish().testFailures.first)

        #expect(failure.note?.contains("first of") == false)
        #expect(failure.note?.contains("two") == true)
    }

    @Test
    func aHaystackOfBlankLinesOnlyIsPrintedAsBefore() throws {
        let failure = try Self.containment(value: ["", "", ""], comment: nil)

        #expect(failure.note?.contains("lines — see the raw log)") == false)
        #expect(failure.note?.contains("first of") == false)
    }
}

private extension RunHaystackCompactionTests {
    static func rendered(_ failure: RunTestFailure) -> String {
        RunFailureShape.of(shapeFailures([failure]), changedFiles: .of([])).rendered().joined(separator: "\n")
    }
}

private extension RunHaystackCompactionTests {
    static let answer = (1 ... 12).map { "line \($0) of the answer: widget \($0 * 7)" }

    /// Lines 18-120 of the log the probe package wrote, the value and comment printed the way Swift Testing prints them.
    static let probeLog: [String] = {
        func value(_ prefix: String, _ depth: String) -> [String] {
            ["↳\(prefix)output → \"\(answer[0])"] + answer.dropFirst().enumerated().map { "\(depth)\($0.element)\($0.offset == 10 ? "\"" : "")" }
        }
        func comment() -> [String] {
            ["↳ \(answer[0])"] + answer.dropFirst().map { "  \($0)" }
        }
        var log = ["✘ Test plainOperand() recorded an issue at GizmoTests.swift:17:5: Expectation failed: output == \"short\"", "↳ output == \"short\" → false"]
        log += value("   ", "    ")
        log += ["✘ Test containsFolded() recorded an issue at GizmoTests.swift:6:5: Expectation failed: output.contains(\"folded in here\")"]
        log += comment() + ["↳ output.contains(\"folded in here\") → false"] + value("   ", "    ")
        log += ["✘ Test secondTest() recorded an issue at GizmoTests.swift:12:5: Expectation failed: output.contains(\"other note\")"]
        log += comment() + ["↳ output.contains(\"other note\") → false"] + value("   ", "    ")
        log += ["✘ Test containsFolded() recorded an issue at GizmoTests.swift:7:5: Expectation failed: !output.contains(\"widget 14\")"]
        log += comment() + ["↳ !output.contains(\"widget 14\") → true", "↳   output.contains(\"widget 14\") → false"] + value("     ", "      ")
        return log
    }()

    static func report(_ lines: [String]) -> RunReport {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in lines {
            filter.consume(line: line)
        }
        return filter.finish()
    }

    static func shapeFailures(_ failures: [RunTestFailure]) -> [RunFailureShape.Failure] {
        failures.map {
            RunFailureShape.Failure(name: $0.name, location: $0.location, message: $0.message, arguments: $0.arguments, note: $0.note, closestLine: $0.closestLine, markedLines: $0.markedLines)
        }
    }

    /// The one failure of `output.contains("x")` with `value` as the receiver's lines and, if given, a comment above the expansions.
    static func containment(value: [String], comment: [String]?, sourceLocation: SourceLocation = #_sourceLocation) throws -> RunTestFailure {
        var lines = ["✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: output.contains(\"x\")"]
        if let comment {
            lines.append("↳ \(comment[0])")
            lines += comment.dropFirst().map { "  \($0)" }
        }
        lines.append("↳ output.contains(\"x\") → false")
        lines.append("↳   output → \"\(value[0])")
        for (offset, line) in value.dropFirst().enumerated() {
            lines.append("    \(line)\(offset == value.count - 2 ? "\"" : "")")
        }
        return try #require(report(lines).testFailures.first, sourceLocation: sourceLocation)
    }
}
