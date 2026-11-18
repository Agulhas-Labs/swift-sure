//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The refusals the set-aside paths really throw, in a checkout that keeps the legacy `.sift/` directory, name that directory: the wiring at each throw site, not only the message built from a name handed to it.
@Suite(.temporaryDirectories)
struct StateDirectoryThrowSiteTests {
    /// A repository with a legacy `.sift/` and one uncommitted change under `Sources/`.
    private func legacyRepository() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("one\n", to: "Sources/a.txt", in: root)
        try TestSources.commitAll(in: root, message: "base")
        try TestSources.write("one, edited\n", to: "Sources/a.txt", in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".sift"), withIntermediateDirectories: true)
        return root
    }

    private func leaveUnrestored(in root: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let store = SetAsideStore(repositoryRoot: root)
        let record = try SetAside.capture(pathspecs: ["Sources/"], from: root, into: store)
        guard case .setAside = try SetAside(store: store).setAside(record) else {
            Issue.record("the set-aside stopped part-way", sourceLocation: sourceLocation)
            return
        }
    }

    private func expectNamesLegacy(_ error: SetAsideError?, containing fragment: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let text = error?.description else {
            Issue.record("no refusal", sourceLocation: sourceLocation)
            return
        }
        #expect(text.contains(fragment), "\(text)", sourceLocation: sourceLocation)
        #expect(!text.contains(".swift-sure"), "\(text)", sourceLocation: sourceLocation)
    }

    @Test
    func theRefusalForARecordLeftBehindNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)

        expectNamesLegacy(SetAsideSession.refusal(for: root), containing: "kept under .sift/set-aside/.")
    }

    @Test
    func aSetAsideStartedOverARecordLeftBehindNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)

        do {
            _ = try SetAsideSession.begin(pathspecs: ["Sources/"], from: root)
            Issue.record("a second set-aside started over an unrestored record")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "kept under .sift/set-aside/.")
        }
    }

    @Test
    func aResetOverARecordLeftBehindNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)

        do {
            try SetAsideSession.clearCache(in: root)
            Issue.record("reset deleted the directory with an unrestored record in it")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "kept under .sift/set-aside/.")
        }
    }

    @Test
    func aRunRefusedWhileAResetHoldsTheTreeNamesTheDirectoryBeingDeleted() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)
        let store = SetAsideStore(repositoryRoot: root)
        let lock = try #require(try SetAsideLock.take(for: store, as: .reset, excludingCache: false))
        defer { lock.release() }

        expectNamesLegacy(SetAsideSession.refusal(for: root), containing: "deleting this working tree's .sift/.")
        do {
            _ = try SetAsideSession.begin(pathspecs: ["Sources/"], from: root)
            Issue.record("a set-aside started while a reset held the tree")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "deleting this working tree's .sift/.")
        }
    }

    @Test
    func aResetRefusedWhileAResetHoldsTheTreeNamesTheDirectoryBeingDeleted() throws {
        let root = try legacyRepository()
        let store = SetAsideStore(repositoryRoot: root)
        let lock = try #require(try SetAsideLock.take(for: store, as: .reset, excludingCache: false))
        defer { lock.release() }

        do {
            try SetAsideSession.clearCache(in: root)
            Issue.record("a second reset ran while one held the tree")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "deleting this working tree's .sift/.")
        }
    }

    @Test
    func leftInPlacePathsNestedUnderTheDirectoryAreNamedByTheDirectoryInUse() throws {
        let root = try legacyRepository()
        try TestSources.write("a\n", to: "Pkg/.sift/a", in: root)
        try TestSources.write("b\n", to: "Pkg/.sift/b", in: root)
        let store = SetAsideStore(repositoryRoot: root)

        do {
            _ = try SetAside.capture(pathspecs: ["Pkg/"], from: root, into: store)
            Issue.record("a set-aside of only this tool's own paths was captured")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "2 paths under .sift/")
        }
    }

    @Test
    func aCaptureOverAnUnrestoredRecordNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)
        try TestSources.write("two\n", to: "Sources/a.txt", in: root)
        let store = SetAsideStore(repositoryRoot: root)

        do {
            _ = try SetAside.capture(pathspecs: ["Sources/"], from: root, into: store)
            Issue.record("a capture ran over an unrestored record")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "kept under .sift/set-aside/.")
        }
    }

    @Test
    func aLineCaptureOverAnUnrestoredRecordNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()
        try leaveUnrestored(in: root)
        try TestSources.write("let a = 1\n", to: "Sources/b.swift", in: root)
        try TestSources.runGit(["add", "Sources/b.swift"], in: root)
        try TestSources.runGit(["commit", "-m", "add b"], in: root)
        let store = SetAsideStore(repositoryRoot: root)

        do {
            _ = try SetAside.capture(line: 1, of: "Sources/b.swift", from: root, into: store)
            Issue.record("a line capture ran over an unrestored record")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "kept under .sift/set-aside/.")
        }
    }

    @Test
    func aRestoreRefusedWhileAResetHoldsTheTreeNamesTheDirectoryBeingDeleted() throws {
        let root = try legacyRepository()
        let store = SetAsideStore(repositoryRoot: root)
        let lock = try #require(try SetAsideLock.take(for: store, as: .reset, excludingCache: false))
        defer { lock.release() }

        do {
            _ = try SetAsideSession.restoreAbandoned(in: root)
            Issue.record("a restore ran while a reset held the tree")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "deleting this working tree's .sift/.")
        }
    }

    @Test
    func aResetThatFindsARecordWrittenBeforeItsLockNamesWhereTheCopiesAreKept() throws {
        let root = try legacyRepository()

        do {
            try SetAsideSession.clearCache(in: root) { try? leaveUnrestored(in: root) }
            Issue.record("reset deleted the directory with a record written before its lock")
        } catch let error as SetAsideError {
            expectNamesLegacy(error, containing: "kept under .sift/set-aside/.")
        }
    }

    @Test
    func theHelperFindsTheDirectoryAtAnyDepth() {
        #expect(SiftPaths.directoryName(holding: ["Pkg/.sift/a", "Pkg/.sift/b"]) == ".sift")
    }
}
