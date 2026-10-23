//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the three rules that make the checkout's parent a product folder, and what the gate does when a rule fails or its environment interferes.
///
/// Every fixture is the same portfolio: `root/Parent/Home` is the checkout, beside the repository `Sibling` in `Parent`, and the repository `Gizmo` sits in `root` beside `Parent`. `Gizmo` is learned only when `Parent` is read as a product folder.
@Suite(.temporaryDirectories)
struct PrivacyGateProductFolderTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    /// The portfolio in `root`, with the named repositories made beside the checkout; returns the checkout.
    private static func portfolio(in root: URL, repositoriesInParent: [String] = ["Sibling"]) throws -> URL {
        let home = root.appending(path: "Parent/Home")
        for file in ["Distribution/verify-private.sh", "Distribution/private-terms.txt"] {
            let destination = home.appending(path: file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repository.appending(path: file), to: destination)
        }
        try TestSources.runGit(["init", "-b", "main"], in: home)
        try TestSources.runGit(["config", "user.email", "tester@example.invalid"], in: home)
        for path in repositoriesInParent.map({ "Parent/\($0)" }) + ["Gizmo"] {
            let directory = root.appending(path: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try TestSources.runGit(["init", "-b", "main"], in: directory)
        }

        return home
    }

    /// Runs the gate from `home` over a file reading `text`, with no `GIT_*` variable in its environment apart from `extra`.
    private static func gate(_ text: String, in root: URL, invokedAt home: URL, extra: [String: String] = [:]) throws -> Verdict {
        let document = root.appending(path: "document.txt")
        try text.write(to: document, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [home.appending(path: "Distribution/verify-private.sh").path, document.path]
        var environment = ProcessEnvironment.withoutGit()
        for (name, value) in extra {
            environment[name] = value
        }
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Read before waiting, so a run that prints more than a pipe holds cannot deadlock.
        _ = output.fileHandleForReading.readDataToEndOfFile()
        let printed = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        return Verdict(status: process.terminationStatus, standardError: printed)
    }

    private static var namesGizmo: String {
        "a screenshot taken in Gizmo on launch.\n"
    }

    /// The control the other tests are read against: a plain product folder learns `Gizmo` and fails the file.
    @Test
    func aProductFolderLearnsTheProjectsBesideIt() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root)

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home)

        #expect(verdict.status == 1, "the control did not learn the project beside the product folder")
        #expect(verdict.standardError.isEmpty, "a plain product folder printed a note")
    }

    /// An inherited git directory does not change which repository the gate asks about.
    @Test
    func anInheritedGitDirectoryDoesNotChangeTheVerdict() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root)
        let elsewhere = root.deletingLastPathComponent().appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try TestSources.runGit(["init", "-b", "main"], in: elsewhere)

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home, extra: ["GIT_DIR": elsewhere.appending(path: ".git").path])

        #expect(verdict.status == 1, "an inherited GIT_DIR pointed the product-folder test at another repository")
    }

    /// A folder that is itself inside a git work tree is not a product folder: discovery stays beside the checkout.
    @Test
    func aFolderInsideAWorkTreeIsNotAProductFolder() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root)
        try TestSources.runGit(["init", "-b", "main"], in: root.appending(path: "Parent"))

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home)

        #expect(verdict.status == 0, "a folder inside a work tree was read as a product folder")
    }

    /// A checkout alone in its folder is not a product folder: with nothing beside it the gate exits 2.
    @Test
    func aCheckoutAloneInItsFolderIsNotAProductFolder() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositoriesInParent: [])

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home)

        #expect(verdict.status == 2, "a checkout alone in its folder was read as a product folder")
    }

    /// A directory that is not a repository keeps the folder from being a product folder, and the gate says so.
    @Test
    func aPlainDirectoryBesideRepositoriesIsNamedInANote() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root)
        try FileManager.default.createDirectory(at: root.appending(path: "Parent/Scratchpad"), withIntermediateDirectories: true)

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home)

        #expect(verdict.status == 0, "the note changed the verdict")
        #expect(verdict.standardError.contains("note:"), "no note was printed")
        #expect(verdict.standardError.contains("Scratchpad"), "the note does not name the directory")
        #expect(verdict.standardError.contains("stayed in the checkout's folder"), "the note does not say discovery stayed put")
    }

    /// A symlink to a plain directory is one too.
    @Test
    func aSymlinkToAPlainDirectoryIsNamedInANote() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root)
        let target = root.appending(path: "Scratchpad")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Parent/Linked"), withDestinationURL: target)

        let verdict = try Self.gate(Self.namesGizmo, in: root, invokedAt: home)

        #expect(verdict.standardError.contains("Linked"), "a symlink to a plain directory went unnoticed")
    }
}

private extension PrivacyGateProductFolderTests {
    /// What one run of the gate printed and how it ended.
    struct Verdict {
        let status: Int32
        let standardError: String
    }
}
