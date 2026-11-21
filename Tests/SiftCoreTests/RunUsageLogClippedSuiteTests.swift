//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A suite filed for a long test name is keyed by the name as the log clips it.
@Suite(.temporaryDirectories)
struct RunUsageLogClippedSuiteTests {
    /// The names are clipped before the suites are matched to them, so a name past the cap keeps its suite under the clipped key.
    @Test
    func aNamePastTheCapKeepsItsSuiteUnderTheClippedKey() throws {
        let file = try TemporaryDirectory.make("run-log")
            .appendingPathComponent("run-log", isDirectory: true)
            .appendingPathComponent("run.jsonl")
        let name = String(repeating: "a", count: RunUsageLog.testNameCap + 40) + "()"
        let clipped = String(name.prefix(RunUsageLog.testNameCap)) + "…"
        let answer = RunUsageLog.Answer(lines: 4, failedTests: [name], failedSuites: [name: "PalletTests"])

        RunUsageLog(fileURL: file).record(logKey: "swift test", exitCode: 1, answer: answer, repositoryRoot: nil, milliseconds: 10)

        let line = try #require(String(contentsOf: file, encoding: .utf8).split(separator: "\n").first)
        let entry = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        #expect(entry["failedSuites"] as? [String: String] == [clipped: "PalletTests"])
    }
}
