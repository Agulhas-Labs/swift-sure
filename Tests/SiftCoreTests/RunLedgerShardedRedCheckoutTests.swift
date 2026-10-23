//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A refusal that names a sharded red's logs says in which checkout they are, whenever that is not the checkout asking.
@Suite(.serialized)
struct RunLedgerShardedRedCheckoutTests {
    private static let toolchain = ToolchainIdentity(description: "Apple Swift version 6.4 · Target: arm64-apple-macosx26.0")
    private static let tree = TreeKey(value: "4f2a9c1e0000000000000000000000000000abcd")
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(ago seconds: TimeInterval, checkout: String, sharded: Bool) -> RunLedger.Record {
        RunLedger.Record(
            tree: Self.tree.value,
            command: "swift test",
            toolchain: Self.toolchain.description,
            finishedAt: Self.now.addingTimeInterval(-seconds),
            log: nil,
            milliseconds: 1000,
            checkout: checkout,
            runToken: sharded ? "1a2b3c4d" : nil,
            shards: sharded ? 3 : nil
        )
    }

    private func refusal(of ledger: RunLedger, from checkout: String, sourceLocation: SourceLocation = #_sourceLocation) -> String? {
        let trust = ledger.trust(tree: Self.tree, command: "swift test", toolchain: Self.toolchain, checkout: checkout, now: Self.now, environment: [:])
        guard case let .notProved(.laterRunFailed(_, _, sharded)) = trust else {
            Issue.record("not a later-run refusal: \(trust)", sourceLocation: sourceLocation)
            return nil
        }
        return sharded
    }

    @Test
    func aRedFromAnotherCheckoutNamesThatCheckoutsLogsAfterAGreen() throws {
        try TemporaryDirectory.withScope {
            let ledger = try RunLedger(fileURL: TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName))
            ledger.record(record(ago: 300, checkout: "/work/a", sharded: true))
            ledger.recordFailure(record(ago: 120, checkout: "/work/b", sharded: true))

            #expect(refusal(of: ledger, from: "/work/a") == "run by \(ProductName.current.binary) test --shards 3 (logs /work/b/\(SiftPaths.directoryName)/runs/*run-*-r1a2b3c4d.log)")
        }
    }

    @Test
    func aRedFromAnotherCheckoutNamesThatCheckoutsLogsWithNoGreenOnFile() throws {
        try TemporaryDirectory.withScope {
            let ledger = try RunLedger(fileURL: TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName))
            ledger.recordFailure(record(ago: 120, checkout: "/work/b", sharded: true))

            #expect(refusal(of: ledger, from: "/work/a")?.contains("(logs /work/b/\(SiftPaths.directoryName)/runs/") == true)
        }
    }

    @Test
    func aRedFromThisCheckoutNamesItsLogsRelatively() throws {
        try TemporaryDirectory.withScope {
            let ledger = try RunLedger(fileURL: TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName))
            ledger.record(record(ago: 300, checkout: "/work/a", sharded: true))
            ledger.recordFailure(record(ago: 120, checkout: "/work/a", sharded: true))

            #expect(refusal(of: ledger, from: "/work/a")?.contains("(logs \(SiftPaths.directoryName)/runs/") == true)
        }
    }

    /// A run with no token names no logs, from whichever checkout it is asked.
    @Test
    func aRedWithNoTokenNamesNoLogs() throws {
        try TemporaryDirectory.withScope {
            let ledger = try RunLedger(fileURL: TestSources.makeTempDirectory().appendingPathComponent(RunLedger.fileName))
            ledger.recordFailure(record(ago: 120, checkout: "/work/b", sharded: false))

            #expect(refusal(of: ledger, from: "/work/a") == nil)
        }
    }

    /// An interrupted red carries its token before the plan is known, so the phrase reads right without a shard count.
    @Test
    func aTokenWithNoShardCountReadsAsARunByTheCommand() {
        let record = RunLedger.Record(tree: Self.tree.value, command: "swift test", toolchain: "any", finishedAt: Self.now, log: nil, milliseconds: 1, runToken: "1a2b3c4d")

        #expect(record.runDescription == "run by \(ProductName.current.binary) test (logs \(SiftPaths.directoryName)/runs/*run-*-r1a2b3c4d.log)")
    }
}
