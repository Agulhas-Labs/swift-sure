//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A `--without` answer whose tests did not compile without the change names `--without-line` as the way to prove a fix that adds API a test names, and only that answer does.
@Suite(.temporaryDirectories)
struct RunWithoutGuardingLineHintTests {
    private static var hint: String {
        "  the tests could not build without the change, so to prove a fix that adds API a test names, rerun with swift-sure run --without-line <file>:<line> on one guarding line"
    }

    /// Tests that did not compile without the change cannot show a failing assertion, so the answer says what to rerun with.
    @Test
    func aRunWhoseTestsDidNotCompileNamesTheGuardingLineForm() throws {
        let directory = try RunWithoutAnswerTests.directory(holding: ["Tests/WidgetTests/WidgetTests.swift": "import Testing\n@testable import Widgets\n"])
        let without = RunWithoutAnswerTests.failedBeforeTests("Tests/WidgetTests/WidgetTests.swift:3:5: error: cannot find 'Gadget' in scope\n")

        let text = RunWithoutAnswerTests.judged(without: without, with: RunWithoutAnswerTests.run(["shoutingWorks()": true]), workingDirectory: directory).render().text
        let lines = text.split(separator: "\n").map(String.init)

        #expect(lines.filter { $0 == Self.hint }.count == 1, "\(text)")
    }

    /// A run without the change that built, and failed an assertion, has no use for the hint.
    @Test
    func aRunWithoutTheChangeThatBuiltDoesNotNameIt() {
        let text = RunWithoutAnswerTests.judged(
            without: RunWithoutAnswerTests.run(["shoutingWorks()": false]),
            with: RunWithoutAnswerTests.run(["shoutingWorks()": true])
        ).render().text

        #expect(!text.contains("--without-line"), "\(text)")
    }
}
