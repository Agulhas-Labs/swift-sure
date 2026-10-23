//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The pointer a checkout's `where` answer gives to the build help topic names the root when run from another directory would build the caller's checkout.
@Suite(.temporaryDirectories)
struct CheckoutPointerRootTests {
    private static var elsewhere: String {
        "/Users/Shared/some-other-checkout"
    }

    private static var pointer: String {
        "how to build one: swift-sure help answers, section (index store)"
    }

    private static func line(root: URL, currentDirectory: String?, rejected: [String] = []) -> String {
        let note = SiftEngine.noStoreNote(for: WorkingTree(repository: "Depot"), rejected: rejected, root: root, currentDirectory: currentDirectory)
        return DegradedNote(cause: SiftEngine.whereNoStoreCause(from: note), withheld: .calls).line
    }

    @Test func aCheckoutPointerFromAnotherDirectoryNamesTheRoot() throws {
        let root = try TestSources.makeTempRepo()
        let line = Self.line(root: root, currentDirectory: Self.elsewhere)

        #expect(line.hasSuffix("; \(Self.pointer); run that build with --root \(TestRunRequest.shellQuoted(root.path))"), "\(line)")
    }

    @Test func aCheckoutPointerFromTheRootIsUnchanged() throws {
        let root = try TestSources.makeTempRepo()

        #expect(Self.line(root: root, currentDirectory: root.path) == "no store for callers, overrides or references; sites by written name; \(Self.pointer)")
    }

    @Test func theRootClauseGoesWithTheRemedyAndLeavesWhatFollows() {
        let root = URL(fileURLWithPath: "/Users/Shared/my; checkout")
        let line = Self.line(root: root, currentDirectory: Self.elsewhere, rejected: ["indexStorePath set"])

        #expect(line.contains("run that build with --root '/Users/Shared/my; checkout'"), "\(line)")
        #expect(DegradedNote.withoutRemedy(line) == "no store for callers, overrides or references; sites by written name; passed over: indexStorePath set")
    }

    @Test(arguments: ["/Users/Shared/probe-it's x", "/Users/Shared/probe-q'z"])
    func aRootWithAQuoteLeavesTheClauseThatFollows(path: String) {
        let line = Self.line(root: URL(fileURLWithPath: path), currentDirectory: Self.elsewhere, rejected: ["indexStorePath set"])

        #expect(line.contains("run that build with --root \(TestRunRequest.shellQuoted(path))"), "\(line)")
        #expect(DegradedNote.withoutRemedy(line) == "no store for callers, overrides or references; sites by written name; passed over: indexStorePath set", "\(line)")
    }

    @Test(arguments: ["plain", "a b", "it's", "q'z", "a;b", "'"])
    func theShellWordEndsAtTheQuotedWordsEnd(value: String) {
        let word = TestRunRequest.shellQuoted(value)
        let text = word + "; passed over: x"

        #expect(StoreRemedy.endOfShellWord(in: text, from: text.startIndex) == text.index(text.startIndex, offsetBy: word.count), "\(text)")
    }

    @Test func anUnknownCallerDirectoryAlwaysNamesTheRoot() throws {
        let root = try TestSources.makeTempRepo()

        #expect(StoreRemedy.rootFlag(root: root, currentDirectory: nil) == "--root \(TestRunRequest.shellQuoted(root.path)) ")
        #expect(StoreRemedy.rootFlag(root: root, currentDirectory: root.path).isEmpty)
        #expect(Self.line(root: root, currentDirectory: nil).contains("run that build with --root "))
        #expect(SiftEngine.storeStatusLine(discovered: nil, rejected: [], root: root, currentDirectory: nil).contains("swift-sure run --root "))
    }
}
