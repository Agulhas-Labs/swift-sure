//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The build commands a no-store note offers name the answer's root when it is not the directory SwiftSure is running in, since run from there the bare form builds the caller's checkout instead.
@Suite(.temporaryDirectories)
struct NoStoreRemedyRootTests {
    private static var elsewhere: String {
        "/Users/Shared/some-other-checkout"
    }

    private static func packageRoot() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("// swift-tools-version:6.0\nimport PackageDescription\n", to: "Package.swift", in: root)
        return root
    }

    @Test func aWorktreeNoteFromAnotherDirectoryNamesTheRoot() throws {
        let root = try Self.packageRoot()
        let note = SiftEngine.noStoreNote(for: WorkingTree(repository: "Depot", worktree: "w"), root: root, currentDirectory: Self.elsewhere)

        #expect(note.contains("build one with `swift-sure run --root \(TestRunRequest.shellQuoted(root.path)) -- swift build --build-tests`"), "\(note)")
    }

    @Test func aCheckoutNoteAndTheStatusLineNameTheRootInBothCommands() throws {
        let root = try Self.packageRoot()
        let flag = "--root \(TestRunRequest.shellQuoted(root.path)) "
        let note = SiftEngine.noStoreNote(for: WorkingTree(repository: "Depot"), root: root, currentDirectory: Self.elsewhere)
        let status = SiftEngine.storeStatusLine(discovered: nil, rejected: [], root: root, currentDirectory: Self.elsewhere)

        for line in [note, status] {
            #expect(line.contains("swift-sure run \(flag)-- swift build --build-tests"), "\(line)")
            #expect(!line.contains("xcodebuild"), "\(line)")
        }
    }

    @Test func aRootWithSpacesIsQuoted() {
        let root = URL(fileURLWithPath: "/Users/Shared/my checkout")

        #expect(StoreRemedy.rootFlag(root: root, currentDirectory: Self.elsewhere) == "--root '/Users/Shared/my checkout' ")
    }

    @Test func theRootItselfKeepsTheTextUnchanged() throws {
        let root = try Self.packageRoot()
        let link = try TemporaryDirectory.make("link").appendingPathComponent("to-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)

        for tree in [WorkingTree(repository: "Depot"), WorkingTree(repository: "Depot", worktree: "w")] {
            let plain = SiftEngine.noStoreNote(for: tree, root: root, currentDirectory: root.path)
            #expect(!plain.contains("--root"), "\(plain)")
            #expect(SiftEngine.noStoreNote(for: tree, root: root, currentDirectory: link.path) == plain)
        }

        #expect(SiftEngine.noStoreNote(for: WorkingTree(repository: "Depot", worktree: "w"), root: root, currentDirectory: root.path)
            .contains("build one with `swift-sure run -- swift build --build-tests` (`swift-sure help worktree-index`"))
        #expect(!SiftEngine.storeStatusLine(discovered: nil, rejected: [], root: root, currentDirectory: root.path).contains("--root"))
    }

    @Test func theDegradedNoteCarriesTheRootAndStripsWithIt() throws {
        let root = try Self.packageRoot()
        let flag = "--root \(TestRunRequest.shellQuoted(root.path)) "
        let tree = WorkingTree(repository: "Depot", worktree: "w")

        let named = SiftEngine.noStoreNote(for: tree, root: root, currentDirectory: Self.elsewhere)
        let line = DegradedNote(cause: SiftEngine.whereNoStoreCause(from: named), withheld: .calls).line
        #expect(line == "no store for callers, overrides or references; sites by written name; "
            + "build: swift-sure run \(flag)-- swift build --build-tests (swift-sure help worktree-index)")
        #expect(DegradedNote.withoutRemedy(line) == "no store for callers, overrides or references; sites by written name")

        let here = SiftEngine.noStoreNote(for: tree, root: root, currentDirectory: root.path)
        #expect(DegradedNote(cause: SiftEngine.whereNoStoreCause(from: here), withheld: .calls).line
            == "no store for callers, overrides or references; sites by written name; "
            + "build: swift-sure run -- swift build --build-tests (swift-sure help worktree-index)")
    }
}
