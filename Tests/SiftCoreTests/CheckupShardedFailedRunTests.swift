//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A sharded red has no single log, so checkup's failed finding names the run's logs, in their own checkout where that is not this one.
@Suite(.serialized)
struct CheckupShardedFailedRunTests {
    private static func record(checkout: String) -> RunLedger.Record {
        RunLedger.Record(tree: CheckupFailedRunTests.tree.value, command: "swift test", toolchain: CheckupFailedRunTests.toolchain.description, finishedAt: CheckupFailedRunTests.now.addingTimeInterval(-120), log: nil, milliseconds: 1000, checkout: checkout, arguments: ["swift", "test"], exitCode: 1, stoppedBySift: false, runToken: "1a2b3c4d", shards: 3)
    }

    private func findingText(checkout: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
        let ledger = try CheckupFailedRunTests.ledger()
        ledger.recordFailure(Self.record(checkout: checkout))
        let (findings, _) = try await CheckupFailedRunTests.check(ledger)
        return try #require(findings.first, sourceLocation: sourceLocation).text
    }

    @Test
    func aShardedRedFromThisCheckoutNamesItsLogsRelatively() async throws {
        try await TemporaryDirectory.withScope {
            let text = try await findingText(checkout: "/repo")

            #expect(text.contains("(exit 1; run by \(ProductName.current.binary) test --shards 3 (logs \(SiftPaths.directoryName)/runs/*run-*-r1a2b3c4d.log))"))
        }
    }

    @Test
    func aShardedRedFromAnotherCheckoutNamesThatCheckoutsLogs() async throws {
        try await TemporaryDirectory.withScope {
            let text = try await findingText(checkout: "/other")

            #expect(text.contains("(logs /other/\(SiftPaths.directoryName)/runs/*run-*-r1a2b3c4d.log)"))
        }
    }
}
