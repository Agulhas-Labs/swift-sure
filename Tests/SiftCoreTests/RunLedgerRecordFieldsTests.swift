//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A ledger record keeps the run's argv and, for a red one, the exit code and whether SwiftSure stopped it; a record an older SwiftSure wrote still reads.
struct RunLedgerRecordFieldsTests {
    private static var olderRecord: String {
        """
        [{"tree":"4f2a9c1e0000000000000000000000000000abcd","command":"swift test","toolchain":"Apple Swift version 6.4","finishedAt":"2026-10-20T09:21:01Z","milliseconds":1200}]
        """
    }

    @Test
    func aRecordWithoutTheNewFieldsDecodesAndReadsAsNarrowed() throws {
        try TemporaryDirectory.withScope {
            let url = try TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName)
            try Self.olderRecord.write(to: url, atomically: true, encoding: .utf8)

            let record = try #require(RunLedger(fileURL: url).records().first)

            #expect(record.command == "swift test")
            #expect(record.arguments == nil)
            #expect(record.exitCode == nil)
            #expect(record.stoppedBySift == nil)
        }
    }

    @Test
    func theNewFieldsSurviveTheFile() throws {
        try TemporaryDirectory.withScope {
            let url = try TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName)
            let ledger = RunLedger(fileURL: url)
            ledger.recordFailure(RunLedger.Record(
                tree: "4f2a9c1e0000000000000000000000000000abcd",
                command: "swift test",
                toolchain: "Apple Swift version 6.4",
                finishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                log: nil,
                milliseconds: 5,
                arguments: ["swift", "test", "--filter", "Gizmo"],
                exitCode: 4,
                stoppedBySift: false
            ))

            let record = try #require(ledger.failedRuns.records().first)

            #expect(record.arguments == ["swift", "test", "--filter", "Gizmo"])
            #expect(record.exitCode == 4)
            #expect(record.stoppedBySift == false)
        }
    }
}
