//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The line `run --coverage` opens its section on: the lines the change touched, counted as executable and covered by the coverage data's own rule.
struct CoverageChangedLinesTests {
    private static var path: String {
        "Sources/Kit/Greeter.swift"
    }

    /// An `llvm-cov export` for one function at lines 3–9 whose middle never ran.
    private static let export = Data("""
    {"data":[{"files":[{"filename":"Sources/Kit/Greeter.swift",\
    "segments":[[3,20,1,true,true,false],[5,12,0,true,true,false],[7,10,1,true,false,false],[9,2,0,false,false,false]]}]}]}
    """.utf8)

    /// An `xccov view --archive --file` document: lines 1, 2 and 7 hold no code.
    private static let xccov = Data("""
    {"Sources\\/Kit\\/Greeter.swift":[{"isExecutable":false,"line":1},{"isExecutable":false,"line":2},\
    {"executionCount":8,"isExecutable":true,"line":3},{"executionCount":8,"isExecutable":true,"line":4},\
    {"executionCount":0,"isExecutable":true,"line":5},{"executionCount":9,"isExecutable":true,"line":6},{"isExecutable":false,"line":7}]}
    """.utf8)

    @Test func theLlvmCovPathCountsExecutableAndCoveredLinesAndNamesTheUncoveredRange() throws {
        let counts = try CoverageAnswer.lineCounts(fromExport: Self.export)
        // 1 and 2 are a comment and a blank line, 12 is past the function: none is executable.
        let line = CoverageChangedLines.line(changed: [Self.path: [1, 2, 3, 5, 6, 7, 12]], counts: counts)

        #expect(line == "changed lines: 4 executable, 2 covered; uncovered: Sources/Kit/Greeter.swift:6-7")
    }

    @Test func theXccovPathCountsExecutableAndCoveredLinesAndNamesTheUncoveredRange() throws {
        let counts = try ResultBundleCoverage.lineCounts(fromFile: Self.xccov)
        let line = CoverageChangedLines.line(changed: [Self.path: [1, 2, 3, 5, 7]], counts: counts)

        #expect(line == "changed lines: 2 executable, 1 covered; uncovered: Sources/Kit/Greeter.swift:5")
    }

    @Test func aCommentABlankLineAndABraceAreNeitherExecutableNorUncovered() throws {
        let counts = try ResultBundleCoverage.lineCounts(fromFile: Self.xccov)

        #expect(CoverageChangedLines.line(changed: [Self.path: [1, 2, 7]], counts: counts) == "changed lines: none executable")
    }

    @Test func nothingIsUncoveredWhenEveryExecutableLineRan() throws {
        let counts = try ResultBundleCoverage.lineCounts(fromFile: Self.xccov)

        #expect(CoverageChangedLines.line(changed: [Self.path: [3, 4, 6]], counts: counts) == "changed lines: 3 executable, 3 covered")
    }

    @Test func aChangeInFilesTheRunDidNotMeasureReadsNoneMeasured() {
        #expect(CoverageChangedLines.line(changed: ["Sources/Other.swift": [4]], counts: [Self.path: [3: 1]]) == "changed lines: none measured")
    }

    @Test func aFileNotMeasuredContributesToNeitherCount() {
        let line = CoverageChangedLines.line(changed: [Self.path: [3, 4], "Sources/Other.swift": [1, 2, 3]], counts: [Self.path: [3: 1, 4: 0]])

        #expect(line == "changed lines: 2 executable, 1 covered; uncovered: Sources/Kit/Greeter.swift:4")
    }

    @Test func noChangedLineMeansNoLine() {
        #expect(CoverageChangedLines.line(changed: [:], counts: [Self.path: [3: 1]]) == nil)
    }

    @Test func moreThanFiveRangesAreCutWithACountOfTheRest() {
        let counts: [String: [Int: UInt64]] = ["A.swift": [1: 0, 3: 0, 5: 0, 7: 0], "B.swift": [2: 0, 9: 0, 11: 0]]
        let line = CoverageChangedLines.line(changed: ["A.swift": [1, 3, 5, 7], "B.swift": [2, 9, 11]], counts: counts)

        #expect(line == "changed lines: 7 executable, 0 covered; uncovered: A.swift:1, A.swift:3, A.swift:5, A.swift:7, B.swift:2, +2 more")
    }

    @Test func exactlyFiveRangesAreAllNamed() {
        let counts: [String: [Int: UInt64]] = ["A.swift": [1: 0, 3: 0, 4: 0, 5: 0, 8: 0, 9: 0]]
        let line = CoverageChangedLines.line(changed: ["A.swift": [1, 3, 4, 5, 8, 9]], counts: counts)

        #expect(line == "changed lines: 6 executable, 0 covered; uncovered: A.swift:1, A.swift:3-5, A.swift:8-9")
    }

    @Test func theSectionOpensOnTheLineBeforeAnyDeclaration() throws {
        let counts = try CoverageAnswer.lineCounts(fromExport: Self.export)
        let declaration = ChangedDeclaration(path: Self.path, label: "Greeter.greet()", lines: [3 ... 6])
        let section = CoverageAnswer.render([declaration], counts: counts, change: "the working tree against HEAD", changed: [Self.path: [3, 5, 6]])

        #expect(section.first == "changed lines: 3 executable, 2 covered; uncovered: Sources/Kit/Greeter.swift:6")
        #expect(section[1].hasPrefix("coverage: 1 changed declaration"))
    }
}
