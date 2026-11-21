//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A failed expectation's expansion does not echo the literals it compares against: a string literal's expansion as itself, and a `some` that repeats its parent or a literal of the message.
struct RunExpansionEchoTests {
    @Test
    func aLiteralWithEscapesIsNotExpandedAsItself() {
        #expect(Self.body("multilineLiteral") == [
            #"Expectation failed: note(0) == "first line\nsecond line\nthird line" → false note(0) → nil"#,
        ])
        #expect(Self.body("escapes") == [
            #"Expectation failed: note(0) == "say \"hi\"\tand\\back\nnext" → false note(0) → nil"#,
        ])
    }

    @Test
    func aRawLiteralIsNotExpandedAsItself() {
        #expect(Self.body("rawLiteral") == [
            ##"Expectation failed: note(0) == #"raw \n stays"# → false note(0) → nil"##,
        ])
    }

    @Test
    func aLongLiteralComparedToNilPrintsOnceNotThreeTimes() {
        #expect(Self.body("optionalNilAgainstLiteral") == [
            #"Expectation failed: note(0) == "the expected golden string, about a hundred characters long, so the repeat is plainly visible" → false note(0) → nil"#,
        ])
    }

    @Test
    func anInterpolatedLiteralIsKeptAndItsSomeIsDropped() {
        #expect(Self.body("interpolated") == [
            #"Expectation failed: note(0) == "k is \(k)\nnext" → false note(0) → nil "k is \(k)\nnext" → "k is 5"#,
            #"  next""#,
        ])
    }

    @Test
    func aValueThatIsNotTheQuotedContentsIsKept() {
        #expect(Self.body("customLiteral") == [
            #"Expectation failed: tag() == "lower\ncase" → false tag() → nil "lower\ncase" → Tag(LOWER"#,
            #"  CASE) raw → "LOWER"#,
            #"  CASE""#,
        ])
    }

    @Test
    func aSomeEqualToItsParentOrNoPayloadOfItsParentIsDropped() {
        #expect(Self.body("optionalInt") == [
            "Expectation failed: n == 4 → false n → 3",
        ])
        #expect(Self.body("notEqualSame") == [
            #"Expectation failed: note(1) != "actual value here" → false note(1) → "actual value here""#,
        ])
    }

    @Test
    func aSomeBeneathAParentThatAlreadyHasOneIsDropped() {
        #expect(Self.body("optionalValueAgainstLiteral") == [
            #"Expectation failed: note(1) == "the expected golden string" → false note(1) → "actual value here""#,
        ])
    }

    @Test
    func aSomeWithNoParentIsDroppedWhenItIsALiteralOfTheMessage() {
        #expect(Self.body("literalOnTheLeft") == [
            #"Expectation failed: "plain" == note(1) → false note(1) → "actual value here""#,
        ])
    }

    @Test
    func aSomeNilIsKept() {
        #expect(Self.body("someNil") == [
            #"Expectation failed: settings["k"] == nil → false settings["k"] → nil some → nil"#,
        ])
    }

    @Test
    func aStructPropertyNamedSomeIsKept() {
        #expect(Self.body("pairField") == [
            #"Expectation failed: pair() == Pair(first: "a\nb", some: "x") → false pair() → Pair first → "a"#,
            #"  b" some → "a"#,
            #"  b" Pair(first: "a\nb", some: "x") → Pair first → "a"#,
            #"  b""#,
        ])
        #expect(Self.body("recField").first?.hasPrefix(#"Expectation failed: rec() == Rec(n: 2, some: "a\nc") → false rec() → Rec n → 1 some → "a"#) == true)
        #expect(Self.body("recField").contains { $0.contains(#"Rec(n: 2, some: "a\nc") → Rec n → 2 some → "a"#) })
    }

    @Test
    func aCommentAboveTheExpansionIsNeverRead() {
        #expect(Self.body("commented") == [
            #"Expectation failed: note(0) == "a\nb""#,
            #"↳ a comment note(0) == "a\nb" → false note(0) → nil (by adjacency)"#,
        ])
    }

    @Test
    func aLiteralWhoseLineEndsInASpaceIsStillDropped() {
        let message = #"Expectation failed: note(0) == "a \nb""#
        let note = [
            RunFailureCensus.NoteLine(text: #"note(0) == "a \nb" → false"#, marked: true),
            RunFailureCensus.NoteLine(text: #""a \nb" → "a"#, marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: #"b""#, marked: false),
        ]

        #expect(RunFailureCensus.droppingEchoes(message: message, note: note) == [note[0]])
    }

    @Test
    func aNoteLongerThanTheHeldLimitPrintsAsStreamed() {
        var lines = [#"✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: note(0) == "a\nb""#, #"↳ note(0) == "a\nb" → false"#]
        lines += [#"↳   "a\nb" → "a"#, #"    b""#]
        lines += (0 ..< RunFailureCensus.closestLineNoteLimit.lines).map { "↳   probe\($0) → \($0)" }
        let failure = Self.report(lines).testFailures.first

        #expect(failure?.note?.contains(#""a\nb" → "a"#) == true)
    }

    @Test
    func valuesCompareByUnicodeScalarsNotCanonicalEquivalence() {
        let message = #"Expectation failed: note(0) == "caf\u{E9}\nx""#
        let header = RunFailureCensus.NoteLine(text: #"note(0) == "caf\u{E9}\nx" → false"#, marked: true)
        let decomposed = [
            RunFailureCensus.NoteLine(text: "\"caf\\u{E9}\\nx\" → \"cafe\u{301}", marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: "x\"", marked: false),
        ]
        let precomposed = [
            RunFailureCensus.NoteLine(text: "\"caf\\u{E9}\\nx\" → \"caf\u{E9}", marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: "x\"", marked: false),
        ]

        #expect(RunFailureCensus.droppingEchoes(message: message, note: [header] + decomposed) == [header] + decomposed)
        #expect(RunFailureCensus.droppingEchoes(message: message, note: [header] + precomposed) == [header])
    }

    @Test
    func theNulCarriageReturnQuoteAndUnicodeEscapesDecode() {
        let message = #"Expectation failed: v == "x\0y\ru\'\u{41}\u{1F600}""#
        let header = RunFailureCensus.NoteLine(text: #"v == "x\0y\ru\'\u{41}\u{1F600}" → false"#, marked: true)
        let echo = RunFailureCensus.NoteLine(text: #""x\0y\ru\'\u{41}\u{1F600}" → "# + "\"x\u{0}y\ru'A\u{1F600}\"", marked: true, indent: "  ")

        #expect(RunFailureCensus.droppingEchoes(message: message, note: [header, echo]) == [header])
    }

    @Test
    func aNoteNoLineOfWhichOpensTheMessageDropsNothing() {
        let note = [
            RunFailureCensus.NoteLine(text: #"note(0) == "a\nb" → false"#, marked: true),
            RunFailureCensus.NoteLine(text: "note(0) → nil", marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: #""a\nb" → "a"#, marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: #"b""#, marked: false),
        ]

        #expect(RunFailureCensus.droppingEchoes(message: "Expectation failed: other", note: note) == note)
        #expect(RunFailureCensus.droppingEchoes(message: #"Expectation failed: note(0) == "a\nb""#, note: note).count == 2)
    }

    @Test
    func aLiteralHaystackPrintsItsExpressionAndTheClosestLineClause() {
        #expect(Self.body("literalHaystack") == [
            #"Expectation failed: "x\nyy".contains("zz") → false"#,
            "no line shares text with it",
        ])
    }

    @Test
    func aNoteWithNothingToDropIsAsItStreamed() {
        let failure = Self.failure("plainAgainstLiteral")

        #expect(failure.note == #"plain(1) == "actual 2" → false plain(1) → "actual 1""#)
        #expect(failure.markedLines == [#"plain(1) == "actual 2" → false"#, #"  plain(1) → "actual 1""#])
    }

    @Test
    func droppedLinesDoNotCountTowardTheTwelveLineCap() {
        var lines = [#"✘ Test t() recorded an issue at T.swift:5:5: Expectation failed: note(0) == "a\nb""#, #"↳ note(0) == "a\nb" → false"#, "↳   note(0) → nil"]
        lines += [#"↳   "a\nb" → "a"#, #"    b""#, #"↳     some → "a"#, #"  b""#]
        lines += (1 ... 9).map { "↳   probe\($0) → \($0)" }
        let failure = Self.report(lines).testFailures.first

        #expect(failure?.note?.contains("probe9 → 9") == true)
        #expect(failure?.note?.contains("more lines") == false)
    }

    @Test
    func anArrayLiteralOfStringsIsDroppedWhenItsValueIsTheRenderingOfItsSource() {
        let message = ##"Expectation failed: body() == [#"a "q" b"#, "c\nd",]"##
        let header = RunFailureCensus.NoteLine(text: ##"body() == [#"a "q" b"#, "c\nd",] → false"##, marked: true)
        let actual = RunFailureCensus.NoteLine(text: #"body() → ["x"]"#, marked: true, indent: "  ")
        let echo = RunFailureCensus.NoteLine(text: ##"[#"a "q" b"#, "c\nd",] → ["a \"q\" b", "c\nd"]"##, marked: true, indent: "  ")

        #expect(RunFailureCensus.droppingEchoes(message: message, note: [header, actual, echo]) == [header, actual])
    }

    @Test
    func arrayLiteralsInOtherSpellingsAreDropped() {
        let cases = [
            (#"[ "a" , "b" ]"#, #"["a", "b"]"#),
            (##"[#"raw"#]"##, #"["raw"]"#),
            (#"["\\ \" \' \t \0"]"#, "[\"\\\\ \\\" \\' \\t \\0\"]"),
            (#"[["a"] , ["b"]]"#, #"[["a"], ["b"]]"#),
            ("[ ]", "[]"),
        ]
        for (source, value) in cases {
            let header = RunFailureCensus.NoteLine(text: "x == \(source) → false", marked: true)
            let echo = RunFailureCensus.NoteLine(text: "\(source) → \(value)", marked: true, indent: "  ")

            #expect(RunFailureCensus.droppingEchoes(message: "Expectation failed: x == \(source)", note: [header, echo]) == [header], "\(source)")
        }
    }

    @Test
    func aSomeBeneathADroppedArrayLineIsDropped() {
        let message = #"Expectation failed: x == [ "a" , "b" ]"#
        let note = [
            RunFailureCensus.NoteLine(text: #"x == [ "a" , "b" ] → false"#, marked: true),
            RunFailureCensus.NoteLine(text: #"[ "a" , "b" ] → ["a", "b"]"#, marked: true, indent: "  "),
            RunFailureCensus.NoteLine(text: #"some → ["a", "b"]"#, marked: true, indent: "    "),
        ]

        #expect(RunFailureCensus.droppingEchoes(message: message, note: note) == [note[0]])
    }

    @Test
    func anArrayLiteralWhoseValueDiffersOrWhoseElementIsKeptStays() {
        let cases = [
            (#"["k\(k)", "b"]"#, #"["k5", "b"]"#),
            ("[\"\\u{301}x\"]", "[\"\\u{0301}x\"]"),
            ("[\"\\u{7}\"]", "[\"\\u{07}\"]"),
            (#"["a","b"]"#, #"["b", "a"]"#),
            (#"["lower"]"#, "[Tag(LOWER)]"),
            (#"["k": "v"]"#, #"["k": "v"]"#),
        ]
        for (source, value) in cases {
            let header = RunFailureCensus.NoteLine(text: "x == \(source) → false", marked: true)
            let echo = RunFailureCensus.NoteLine(text: "\(source) → \(value)", marked: true, indent: "  ")

            #expect(RunFailureCensus.droppingEchoes(message: "Expectation failed: x == \(source)", note: [header, echo]) == [header, echo], "\(source)")
        }
    }
}

private extension RunExpansionEchoTests {
    static func report(_ lines: [String]) -> RunReport {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in lines {
            filter.consume(line: line)
        }
        return filter.finish()
    }

    static func failure(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) -> RunTestFailure {
        guard let found = report(probeLog.components(separatedBy: "\n")).testFailures.first(where: { $0.name == "\(name)()" }) else {
            Issue.record("no failure named \(name)", sourceLocation: sourceLocation)
            return RunTestFailure(name: name, location: nil, message: "")
        }
        return found
    }

    /// The rendered lines beneath the failure's own heading.
    static func body(_ name: String) -> [String] {
        let failure = failure(name)
        let shaped = RunFailureShape.Failure(name: failure.name, location: failure.location, message: failure.message, arguments: failure.arguments, note: failure.note, closestLine: failure.closestLine, markedLines: failure.markedLines)
        let rendered = RunFailureShape.of([shaped], changedFiles: .of([])).rendered()
        return (rendered.firstIndex { $0.hasPrefix("  \(failure.name) — ") }.map { Array(rendered[($0 + 1)...]) } ?? rendered).map { String($0.dropFirst(4)) }
    }

    static var probeLog: String {
        ##"""
        ✘ Test optionalNilAgainstLiteral() recorded an issue at ProbeTests.swift:11:42: Expectation failed: note(0) == "the expected golden string, about a hundred characters long, so the repeat is plainly visible"
        ↳ note(0) == "the expected golden string, about a hundred characters long, so the repeat is plainly visible" → false
        ↳   note(0) → nil
        ↳     some → "the expected golden string, about a hundred characters long, so the repeat is plainly visible"
        ✘ Test recField() recorded an issue at ProbeTests.swift:38:25: Expectation failed: rec() == Rec(n: 2, some: "a\nc")
        ↳ rec() == Rec(n: 2, some: "a\nc") → false
        ↳   rec() → Rec
        ↳     n → 1
        ↳     some → "a
              c"
        ↳   Rec(n: 2, some: "a\nc") → Rec
        ↳     n → 2
        ↳     some → "a
              c"
        ✘ Test pairField() recorded an issue at ProbeTests.swift:37:26: Expectation failed: pair() == Pair(first: "a\nb", some: "x")
        ↳ pair() == Pair(first: "a\nb", some: "x") → false
        ↳   pair() → Pair
        ↳     first → "a
              b"
        ↳     some → "a
              b"
        ↳   Pair(first: "a\nb", some: "x") → Pair
        ↳     first → "a
              b"
        ✘ Test plainAgainstLiteral() recorded an issue at ProbeTests.swift:9:36: Expectation failed: plain(1) == "actual 2"
        ↳ plain(1) == "actual 2" → false
        ↳   plain(1) → "actual 1"
        ✘ Test commented() recorded an issue at ProbeTests.swift:31:26: Expectation failed: note(0) == "a\nb"
        ↳ a comment
        ↳ note(0) == "a\nb" → false
        ↳   note(0) → nil
        ↳   "a\nb" → "a
            b"
        ↳     some → "a
              b"
        ✘ Test tripleQuoted() recorded an issue at ProbeTests.swift:21:5: Expectation failed: note(0) == """
                one
                two
                """
        ↳ note(0) == """
                  one
                  two
                  """ → false
        ↳   note(0) → nil
        ↳   """
        ✘ Test someNil() recorded an issue at ProbeTests.swift:35:5: Expectation failed: settings["k"] == nil
        ↳ settings["k"] == nil → false
        ↳   settings["k"] → nil
        ↳     some → nil
        ✘ Test optionalValueAgainstLiteral() recorded an issue at ProbeTests.swift:10:44: Expectation failed: note(1) == "the expected golden string"
        ↳ note(1) == "the expected golden string" → false
        ↳   note(1) → "actual value here"
        ↳     some → "actual value here"
        ↳     some → "the expected golden string"
        ✘ Test escapes() recorded an issue at ProbeTests.swift:13:24: Expectation failed: note(0) == "say \"hi\"\tand\\back\nnext"
        ↳ note(0) == "say \"hi\"\tand\\back\nnext" → false
        ↳   note(0) → nil
        ↳   "say \"hi\"\tand\\back\nnext" → "say "hi"	and\back
            next"
        ↳     some → "say "hi"	and\back
              next"
        ✘ Test customLiteral() recorded an issue at ProbeTests.swift:18:30: Expectation failed: tag() == "lower\ncase"
        ↳ tag() == "lower\ncase" → false
        ↳   tag() → nil
        ↳   "lower\ncase" → Tag(LOWER
            CASE)
        ↳     some → Tag(LOWER
              CASE)
        ↳       raw → "LOWER
                CASE"
        ✘ Test rawLiteral() recorded an issue at ProbeTests.swift:19:27: Expectation failed: note(0) == #"raw \n stays"#
        ↳ note(0) == #"raw \n stays"# → false
        ↳   note(0) → nil
        ↳   #"raw \n stays"# → "raw \n stays"
        ↳     some → "raw \n stays"
        ✘ Test multilineLiteral() recorded an issue at ProbeTests.swift:12:33: Expectation failed: note(0) == "first line\nsecond line\nthird line"
        ↳ note(0) == "first line\nsecond line\nthird line" → false
        ↳   note(0) → nil
        ↳   "first line\nsecond line\nthird line" → "first line
            second line
            third line"
        ↳     some → "first line
              second line
              third line"
        ✘ Test literalOnTheLeft() recorded an issue at ProbeTests.swift:32:33: Expectation failed: "plain" == note(1)
        ↳ "plain" == note(1) → false
        ↳     some → "plain"
        ↳   note(1) → "actual value here"
        ↳     some → "actual value here"
        ✘ Test interpolated() recorded an issue at ProbeTests.swift:16:5: Expectation failed: note(0) == "k is \(k)\nnext"
        ↳ note(0) == "k is \(k)\nnext" → false
        ↳   note(0) → nil
        ↳   "k is \(k)\nnext" → "k is 5
            next"
        ↳     some → "k is 5
              next"
        ✘ Test optionalInt() recorded an issue at ProbeTests.swift:28:5: Expectation failed: n == 4
        ↳ n == 4 → false
        ↳   n → 3
        ↳     some → 3
        ↳     some → 4
        ✘ Test literalHaystack() recorded an issue at ProbeTests.swift:39:32: Expectation failed: "x\nyy".contains("zz")
        ↳ "x\nyy".contains("zz") → false
        ↳   "x\nyy" → "x
            yy"
        ✘ Test notEqualSame() recorded an issue at ProbeTests.swift:30:29: Expectation failed: note(1) != "actual value here"
        ↳ note(1) != "actual value here" → false
        ↳   note(1) → "actual value here"
        ↳     some → "actual value here"
        ↳     some → "actual value here"
        """##
    }
}
