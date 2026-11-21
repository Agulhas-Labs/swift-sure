//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how the `filtered:` line counts a test declared at file scope: as a test, not a suite.
@Suite(.serialized, .temporaryDirectories)
struct FilteredRunReachFileScopeTests {
    @Test
    func aFileScopeTestIsCountedAsATestBesideTheSuites() async throws {
        let root = try await FilteredRunReachHintTests.checkout(dirty: false)
        try TestSources.write("import Testing\n@testable import Lib\n\n@Test func freeStanding() {\n    _ = Widget()\n}\n", to: "Tests/LibTests/WidgetOnly.swift", in: root)
        try TestSources.commitAll(in: root, message: "free test")
        try await SiftEngine(directory: root).ensureFresh()
        try TestSources.write("public struct Widget {\n    public init() {}\n    public var size = 1\n}\n", to: "Sources/Lib/Core.swift", in: root)

        let lines = try FilteredRunReachHintTests.lines(FilteredRunReachHintTests.widgetNames, arguments: FilteredRunReachHintTests.oneFilter, root: root)

        #expect(lines == ["  filtered: the working tree changes Core.swift; 1 suite and 1 test reaching it did not run — run swift test --filter LibTests.GadgetTests --filter 'LibTests\\.freeStanding\\(\\)' (swift-sure affected lists every suite)"])
    }

    @Test
    func theSentenceCountsWhatItLists() {
        func sentence(suites: Int, tests: Int) -> String {
            let entries = (0 ..< suites).map { FilteredRunReachHint.Suite(filter: "LibTests.S\($0)", ran: 0, declared: 1) }
                + (0 ..< tests).map { FilteredRunReachHint.Suite(filter: "LibTests\\.t\($0)\\(\\)", ran: 0, declared: 1, testName: "LibTests.t\($0)()") }
            let line = FilteredRunReachHint(files: ["A.swift"], suites: entries).line ?? ""
            return String(line.split(separator: ";").dropFirst().first ?? "")
        }

        #expect(sentence(suites: 1, tests: 0) == " 1 suite reaching it did not run — run swift test --filter LibTests.S0 (swift-sure affected lists every suite)")
        #expect(sentence(suites: 3, tests: 0).hasPrefix(" 3 suites reaching it"))
        #expect(sentence(suites: 0, tests: 1).hasPrefix(" 1 test reaching it"))
        #expect(sentence(suites: 0, tests: 2).hasPrefix(" 2 tests reaching it"))
        #expect(sentence(suites: 2, tests: 1).hasPrefix(" 2 suites and 1 test reaching it"))
        #expect(sentence(suites: 1, tests: 2).hasPrefix(" 1 suite and 2 tests reaching it"))
    }

    @Test
    func aFileScopeTestRunInPartReadsAsItsFunctionAndTheCommandKeepsTheEscapedFilter() throws {
        let entry = FilteredRunReachHint.Suite(filter: "LibTests\\.freeStanding\\(\\)", ran: 1, declared: 2, testName: "LibTests.freeStanding()")
        let line = try #require(FilteredRunReachHint(files: ["A.swift"], suites: [entry]).line)

        #expect(line == "  filtered: the working tree changes A.swift; 1 test reaching it did not run in full: LibTests.freeStanding() (1 of 2 ran) — run swift test --filter 'LibTests\\.freeStanding\\(\\)' (swift-sure affected lists every suite)")
    }
}
