//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// A failure listing says a test's repeated output once: one excerpt printed under several expectations, and the cases of one parameterized expectation.
struct RunListingFoldTests {
    /// Three failing `.contains` expectations on one twelve-line string each say it in one line, so there is no excerpt left to fold or to point back to.
    @Test
    func threeExpectationsOnOneStringEachSayItInOneLine() throws {
        let lines = Self.answer(logging: Self.containsLog(needles: ["alpha", "beta", "gamma"], lines: 12))
        let start = try #require(lines.firstIndex { $0.hasPrefix("3 failures · 1 signature") })
        let clause = "(first of 12 lines — see the raw log)"

        #expect(Array(lines[(start + 1)...].prefix(9)) == [
            "  render() — GizmoTests.swift:12:9",
            "    Expectation failed: output.contains(\"alpha\") → false output → \"line 1 of the rendered gizmo \(clause)",
            "    no line shares text with it",
            "  render() — GizmoTests.swift:13:9",
            "    Expectation failed: output.contains(\"beta\") → false output → \"line 1 of the rendered gizmo \(clause)",
            "    no line shares text with it",
            "  render() — GizmoTests.swift:14:9",
            "    Expectation failed: output.contains(\"gamma\") → false output → \"line 1 of the rendered gizmo \(clause)",
            "    no line shares text with it",
        ])
        #expect(lines.dropFirst(start + 10).first?.hasPrefix("totals:") == true)
    }

    /// An excerpt that is the first lines of the one printed above folds, and says how many lines its own excerpt runs to.
    @Test
    func anExcerptThatBeginsTheOnePrintedAboveFoldsWithItsOwnCount() {
        let block = Self.listing([
            Self.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["one", "two", "three", "four"]),
            Self.failure(at: "GizmoTests.swift:13:9", expecting: "second", beneath: ["one", "two"]),
        ])

        #expect(Array(block.dropFirst()) == [
            "  render() — GizmoTests.swift:12:9",
            "    Expectation failed: first → false",
            "      one",
            "      two",
            "      three",
            "      four",
            "  render() — GizmoTests.swift:13:9",
            "    Expectation failed: second → false",
            "      (the same 2 lines as under the failure at GizmoTests.swift:12:9 above)",
        ])
    }

    /// A one-line excerpt, a failure with no location and another test's failure each print their excerpt in full.
    @Test
    func aOneLineExcerptAnUnlocatedFailureAndAnanotherTestDoNotFold() {
        let oneLine = Self.listing([
            Self.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["one"]),
            Self.failure(at: "GizmoTests.swift:13:9", expecting: "second", beneath: ["one"]),
        ])
        let unlocated = Self.listing([
            Self.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["one", "two"]),
            Self.failure(at: nil, expecting: "second", beneath: ["one", "two"]),
        ])
        let anotherTest = Self.listing([
            Self.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["one", "two"]),
            Self.failure(named: "restock()", at: "GizmoTests.swift:30:9", expecting: "second", beneath: ["one", "two"]),
        ])

        #expect(oneLine.count { $0 == "      one" } == 2)
        #expect(unlocated.count { $0 == "      two" } == 2)
        #expect(anotherTest.count { $0 == "      two" } == 2)
        #expect(!(oneLine + unlocated + anotherTest).contains { $0.contains("the same") })
    }

    /// Two excerpts that differ only in a temporary directory's name are both printed, since the comparison is exact.
    @Test
    func excerptsThatDifferInATemporaryPathDoNotFold() {
        let block = Self.listing([
            Self.failure(at: "GizmoTests.swift:12:9", expecting: "first", beneath: ["wrote /tmp/gizmo-a1/out.txt", "done"]),
            Self.failure(at: "GizmoTests.swift:13:9", expecting: "second", beneath: ["wrote /tmp/gizmo-b2/out.txt", "done"]),
        ])

        #expect(block.contains("      wrote /tmp/gizmo-a1/out.txt"))
        #expect(block.contains("      wrote /tmp/gizmo-b2/out.txt"))
        #expect(block.count { $0 == "      done" } == 2)
        #expect(!block.contains { $0.contains("the same") })
    }

    /// Five cases failing one expectation print one block for the case first in argument order, whatever order they arrived in, naming the other four sorted.
    @Test(arguments: [[3, 1, 5, 2, 4], [5, 4, 3, 2, 1]])
    func fiveCasesOfOneExpectationPrintOneBlock(order: [Int]) {
        let block = Self.listing(order.map { Self.fitsCase($0) })

        #expect(block == [
            "5 failures · 1 signature · 1 file · 0 in changed files (matched by name)",
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9",
            "    Expectation failed: gizmo.fits → false",
            "    … and 4 more cases of this expectation: size → 2, size → 3, size → 4, size → 5",
        ])
    }

    /// Cases whose notes differ are still one group, and the line naming the others says their values differ.
    @Test
    func casesWhoseNotesDifferSaySo() {
        let block = Self.listing((1 ... 3).map { Self.fitsCase($0, beneath: ["gizmo → Gizmo(size: \($0))"]) })

        #expect(Array(block.dropFirst()) == [
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9",
            "    Expectation failed: gizmo.fits → false",
            "      gizmo → Gizmo(size: 1)",
            "    … and 2 more cases of this expectation: size → 2, size → 3 (their values differ — see the raw log)",
        ])
    }

    /// One parameterized test failing at two locations prints a group for each, each at the place its first case was listed.
    @Test
    func twoLocationsInOneParameterizedTestAreTwoGroups() {
        let block = Self.listing([
            Self.fitsCase(2, at: "GizmoTests.swift:21:9"),
            Self.ordinary("restock()"),
            Self.fitsCase(2),
            Self.fitsCase(1, at: "GizmoTests.swift:21:9"),
            Self.fitsCase(1),
        ])

        #expect(Array(block.dropFirst()) == [
            "  fits(size:) with size → 1 — GizmoTests.swift:21:9",
            "    Expectation failed: gizmo.fits → false",
            "    … and 1 more case of this expectation: size → 2",
            "  restock() — GizmoTests.swift:40:9",
            "    Expectation failed: depot.isEmpty",
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9",
            "    Expectation failed: gizmo.fits → false",
            "    … and 1 more case of this expectation: size → 2",
        ])
    }

    /// Messages that differ only in an error code are two failures, not one group, since the code may be what a fix needs.
    @Test
    func messagesDifferingOnlyInDigitsDoNotGroup() {
        let failures = [("1", "260"), ("2", "4")].map { size, code in
            RunFailureShape.Failure(name: "load(size:)", location: "GizmoTests.swift:30:9", message: "Caught error: Depot refused the load, Code=\(code)", arguments: "size → \(size)")
        }
        let block = Self.listing(failures)

        #expect(Array(block.dropFirst()) == [
            "  load(size:) with size → 1 — GizmoTests.swift:30:9",
            "    Caught error: Depot refused the load, Code=260",
            "  load(size:) with size → 2 — GizmoTests.swift:30:9",
            "    Caught error: Depot refused the load, Code=4",
        ])
    }

    /// A case read from the event stream is listed on its own, beside the group the others form.
    @Test
    func aCaseReadFromTheEventStreamIsNotGrouped() {
        let streamed = RunFailureShape.Failure(name: "fits(size:)", location: "GizmoTests.swift:20:9", message: "Expectation failed: gizmo.fits", arguments: "size → 0", note: "gizmo.fits → false", readFromStream: true)
        let block = Self.listing([streamed, Self.fitsCase(2), Self.fitsCase(1)])

        #expect(Array(block.dropFirst()) == [
            "  fits(size:) with size → 0 — GizmoTests.swift:20:9 (from the event stream)",
            "    Expectation failed: gizmo.fits → false",
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9",
            "    Expectation failed: gizmo.fits → false",
            "    … and 1 more case of this expectation: size → 2",
        ])
    }

    /// A case that failed twice at one location is named once with its count, and the printed case's own repeat is counted on its heading.
    @Test
    func aCaseFailingTwiceAtOneLocationIsCounted() {
        let otherTwice = Self.listing([Self.fitsCase(1), Self.fitsCase(2), Self.fitsCase(2)])
        let printedTwice = Self.listing([Self.fitsCase(1), Self.fitsCase(2), Self.fitsCase(1)])

        #expect(Array(otherTwice.dropFirst()) == [
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9",
            "    Expectation failed: gizmo.fits → false",
            "    … and 1 more case of this expectation: size → 2 ×2",
        ])
        #expect(Array(printedTwice.dropFirst()) == [
            "  fits(size:) with size → 1 — GizmoTests.swift:20:9  ×2",
            "    Expectation failed: gizmo.fits → false",
            "    … and 1 more case of this expectation: size → 2",
        ])
    }

    /// Five failures whose excerpts printed whole would pass the listing budget are still listed, since each entry is charged as it prints folded.
    @Test
    func aListingThatFitsOnlyFoldedIsServedAsAListing() {
        let excerpt = (1 ... 10).map { "row \($0) " + String(repeating: "of the long rendered gizmo ", count: 7) }
        let failures = ["alpha", "beta", "gamma", "delta", "epsilon"].enumerated().map { offset, needle in
            Self.failure(at: "GizmoTests.swift:\(12 + offset):9", expecting: "output.contains(\(needle))", beneath: excerpt)
        }
        let unfolded = excerpt.reduce(0) { $0 + $1.utf8.count + 7 } * failures.count
        let block = Self.listing(failures)

        #expect(unfolded > RunFailureCensus.listingBudget)
        #expect(block.first == "5 failures · 5 signatures · 1 file · 0 in changed files (matched by name)")
        #expect(block.count { $0.hasPrefix("  render() — GizmoTests.swift:") } == 5)
        #expect(block.count { $0 == "      (the same 10 lines as under the failure at GizmoTests.swift:12:9 above)" } == 4)
    }
}

extension RunListingFoldTests {
    /// The answer `swift-sure run` prints for `log`, a Swift Testing run's output, one entry per line.
    static func answer(logging log: [String]) -> [String] {
        var filter = RunOutputFilter(expecting: .runTally)
        for line in log {
            filter.consume(line: line)
        }
        return RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Gizmo"))
            .render(filter.finish(), exitCode: 1, logURL: nil)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// One test's `#expect(output.contains(needle))` failing once per needle, from line 12 on, against one string of `count` lines.
    static func containsLog(needles: [String], lines count: Int) -> [String] {
        let rest = (2 ... count).map { "    line \($0) of the rendered gizmo" }
        var log: [String] = []
        for (offset, needle) in needles.enumerated() {
            log.append("✘ Test render() recorded an issue at GizmoTests.swift:\(12 + offset):9: Expectation failed: output.contains(\"\(needle)\")")
            log.append("↳ output.contains(\"\(needle)\") → false")
            log.append("↳   output → \"line 1 of the rendered gizmo")
            log.append(contentsOf: rest.dropLast())
            log.append((rest.last ?? "") + "\"")
        }
        log.append("✘ Test render() failed after 0.002 seconds with \(needles.count) issues.")
        return log
    }

    /// The listing of `failures`, measured against no changed files.
    static func listing(_ failures: [RunFailureShape.Failure]) -> [String] {
        RunFailureShape.of(failures, changedFiles: .of([])).rendered()
    }

    /// A failed `#expect(expression)` whose note prints `expression → false`, then `beneath`.
    static func failure(named name: String = "render()", at location: String?, expecting expression: String, beneath: [String]) -> RunFailureShape.Failure {
        RunFailureShape.Failure(name: name, location: location, message: "Expectation failed: \(expression)", note: (["\(expression) → false"] + beneath).joined(separator: "\n"))
    }

    /// The case `size → size` of `fits(size:)` failing `#expect(gizmo.fits)` at `location`, its note's lines beneath the first being `beneath`.
    static func fitsCase(_ size: Int, at location: String = "GizmoTests.swift:20:9", beneath: [String] = []) -> RunFailureShape.Failure {
        RunFailureShape.Failure(
            name: "fits(size:)",
            location: location,
            message: "Expectation failed: gizmo.fits",
            arguments: "size → \(size)",
            note: (["gizmo.fits → false"] + beneath).joined(separator: "\n")
        )
    }

    /// An ordinary failure of `name`, which no other failure groups or folds with.
    static func ordinary(_ name: String) -> RunFailureShape.Failure {
        RunFailureShape.Failure(name: name, location: "GizmoTests.swift:40:9", message: "Expectation failed: depot.isEmpty")
    }
}
