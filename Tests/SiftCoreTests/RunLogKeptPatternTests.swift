//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The glob a receipt or refusal prints for a run's logs matches every log of that run, and no other run's.
struct RunLogKeptPatternTests {
    private func matches(_ name: String, token: String) -> Bool {
        let pattern = RunLog.pattern(forRun: token)
        let prefix = "\(SiftPaths.directoryName)/\(RunLog.runsDirectoryName)/"
        return pattern.hasPrefix(prefix) && fnmatch(String(pattern.dropFirst(prefix.count)), name, 0) == 0
    }

    @Test
    func aPlainLogOfTheRunMatches() {
        #expect(matches("run-20261022-101500Z-0a1b2c3d-r1a2b3c4d.log", token: "1a2b3c4d"))
    }

    @Test
    func aShardLogKeptBecauseItLostTestsMatches() {
        #expect(matches("kept-run-20261022-101500Z-0a1b2c3d-r1a2b3c4d.log", token: "1a2b3c4d"))
    }

    @Test
    func anotherRunsLogsAndOtherFilesDoNot() {
        #expect(!matches("run-20261022-101500Z-0a1b2c3d-r99999999.log", token: "1a2b3c4d"))
        #expect(!matches("kept-run-20261022-101500Z-0a1b2c3d-r99999999.log", token: "1a2b3c4d"))
        #expect(!matches("run-20261022-101500Z-0a1b2c3d-r1a2b3c4d.log.part", token: "1a2b3c4d"))
        #expect(!matches("run-20261022-101500Z-0a1b2c3d-r01a2b3c4d.log", token: "1a2b3c4d"))
    }
}
