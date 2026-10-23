//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A failing run whose test bundle `xcodebuild` restarted is answered by the filter, not sent to the raw log: the restart is the explanation, named on the totals line.
@Suite(.temporaryDirectories)
struct RunRestartedRunIsExplainedTests {
    private static var marker: String {
        "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches."
    }

    private static var syntheticLog: String {
        [
            "◇ Test run started.",
            "◇ Test adds() started.", "✔ Test adds() passed after 0.001 seconds.",
            "◇ Test multiplies() started.", "", marker, "",
            "◇ Test run started.",
            "◇ Test divides() started.", "✔ Test divides() passed after 0.001 seconds.",
            "✔ Test run with 20 tests in 28 suites passed after 2.016 seconds.",
            "** TEST FAILED **",
        ].joined(separator: "\n") + "\n"
    }

    @Test
    func aRestartedLogThatPrintedAPassedSentenceIsAnsweredThroughTheLauncher() throws {
        let totals = try Self.totals(of: Self.syntheticLog)

        #expect(totals.contains("bundle restarted during multiplies()"))
    }

    @Test
    func theCapturedCrashAndRestartIsAnsweredThroughTheLauncher() throws {
        let totals = try Self.totals(of: TestSources.runOutput("xcodebuild-crash-restart"))

        #expect(totals.contains("bundle restarted during CalculatorTests.testMultiplyCrashesWhenTriggered"))
    }

    /// Runs `log` through a stand-in `xcodebuild` that exits 65 and returns the answer's `totals:` line, failing where no filtered answer was served.
    private static func totals(of log: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let directory = try TemporaryDirectory.make("run-restart-explained")
        let payload = directory.appendingPathComponent("transcript.txt")
        try log.write(to: payload, atomically: true, encoding: .utf8)
        let script = directory.appendingPathComponent("xcodebuild")
        try "#!/bin/sh\ncat '\(payload.path)'\nexit 65\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let outcome = try RunLauncher(workingDirectory: directory, repositoryRoot: nil, runLogDirectory: directory).run([script.path, "test"])
        let answer = try #require(outcome.filteredAnswer(workingDirectory: directory)?.text, sourceLocation: sourceLocation)
        return answer.split(separator: "\n").first { $0.hasPrefix("totals:") }.map(String.init) ?? ""
    }
}
