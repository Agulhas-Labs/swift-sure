//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A checkout an earlier release set up keeps its `.sift/`; what the tool says about the state directory names that one, never the current name's.
@Suite(.temporaryDirectories)
struct StateDirectoryInUseMessageTests {
    private func legacyCheckout() throws -> URL {
        let root = try TemporaryDirectory.make("legacy-state")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".sift"), withIntermediateDirectories: true)
        return root
    }

    @Test
    func theKeepCommandNamesTheStoresOwnParent() {
        let failure = SetAsideError.NotRestored(reasons: ["Sources/a.txt: expected a file, found nothing"], invocation: "--without Sources/", store: ".sift/set-aside/", id: "0123456789", requested: true)

        let text = SetAsideError.notRestored(failure).description

        #expect(text.contains("`mv .sift/set-aside .sift/set-aside-kept-01234567`"))
        #expect(!text.contains(".swift-sure"))
    }

    @Test
    func theSetAsideStoreIsShownUnderTheDirectoryInUse() throws {
        let root = try legacyCheckout()

        #expect(SetAsideStore(repositoryRoot: root).shownDirectory == ".sift/set-aside/")
    }

    @Test
    func theShardRecordIsShownUnderTheDirectoryInUse() throws {
        let root = try legacyCheckout()
        let ledger = try ShardLedger(repositoryRoot: root, runID: "0f9e8d7c", prefix: "a1b2c3", owner: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), started: { _ in nil })

        #expect(ledger.shownFileURL.hasPrefix(".sift/"))
    }

    @Test
    func theDerivedDataLineNamesTheDirectoryTheRunBuiltIn() {
        let line = WorktreeDerivedData.line(for: URL(fileURLWithPath: "/work/tree/.sift/DerivedData"))

        #expect(line.hasPrefix("derived data .sift/DerivedData "))
    }

    @Test
    func aShardedRunsLogPatternNamesTheCheckoutsDirectory() throws {
        let root = try legacyCheckout()
        let record = RunLedger.Record(tree: "t", command: "swift test", toolchain: "x", finishedAt: Date(), log: nil, milliseconds: 1, checkout: root.path, runToken: "1a2b3c4d", shards: 3)

        let text = try #require(record.shardedRun())

        #expect(text.contains("(logs .sift/runs/*run-*-r1a2b3c4d"))
    }
}
