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

    @Test
    func theStoreNamesTheDirectoryItsCheckoutUses() throws {
        let root = try legacyCheckout()

        #expect(SetAsideStore(repositoryRoot: root).stateDirectoryName == ".sift")
    }

    @Test
    func aRefusalForNothingToSetAsideNamesTheDirectoryTheChangesAreIn() {
        let uncommitted = SetAsideError.nothingUncommitted(pathspecs: ["Sources/"], matchesFiles: true, leftInPlace: [".sift/a", ".sift/b"], committedSince: nil).description
        let since = SetAsideError.nothingSince(pathspecs: ["Sources/"], since: "0123456789abcdef", matchesFiles: true, leftInPlace: [".sift/a", ".sift/b"]).description

        #expect(uncommitted.contains("2 paths under .sift/"))
        #expect(since.contains("2 paths under .sift/"))
        #expect(!uncommitted.contains(".swift-sure") && !since.contains(".swift-sure"))
    }

    @Test
    func aResetRefusalNamesTheDirectoryItIsDeleting() {
        let holder = SetAsideLock.Holder(pid: 4711, role: .reset)

        let text = SetAsideError.busy(holder: holder, record: nil, stateDirectory: ".sift").description

        #expect(text.contains("deleting this working tree's .sift/."))
        #expect(!text.contains(".swift-sure"))
    }

    @Test
    func anUnrestoredRefusalNamesWhereTheCopiesAreKept() {
        let record = SetAsideRecord(id: "0123456789", pathspecs: ["Sources/"], directory: "", head: "abc", owner: 4711, entries: [])

        let text = SetAsideError.unrestored(record, stateDirectory: ".sift").description

        #expect(text.contains("kept under .sift/set-aside/."))
        #expect(!text.contains(".swift-sure"))
    }

    @Test
    func theLeftInPlaceLineNamesTheDirectoryTheChangeIsIn() {
        let record = SetAsideRecord(id: "0123456789", pathspecs: ["Sources/"], directory: "", head: "abc", owner: 4711, entries: [], leftInPlace: [".sift/runs/log"])

        let text = RunWithoutAnswer.leftInPlaceLine(record)

        #expect(text.contains("this tool's own .sift/ directory"))
        #expect(!text.contains(".swift-sure"))
    }

    @Test
    func theSemanticCacheNoteNamesTheCheckoutsDirectory() throws {
        let root = try legacyCheckout()
        let refusal = CocoaError(.fileWriteNoPermission)

        let text = SemanticOpenFailure.cause(of: refusal, in: root)

        #expect(text.contains("the semantic cache under .sift/ cannot be written"))
    }
}
