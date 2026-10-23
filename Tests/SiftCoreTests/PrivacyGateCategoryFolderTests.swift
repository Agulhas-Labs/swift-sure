//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how the release-time gate reads the level above a product folder, where a folder may group a kind of project rather than be one.
///
/// Every fixture is the same portfolio: `root/Parent/Home` is the checkout, a git repository carrying the check, beside the repository `Sibling` in the product folder `Parent`; what sits beside `Parent` in `root` is each test's subject.
@Suite(.temporaryDirectories)
struct PrivacyGateCategoryFolderTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    /// The check itself and the list it reads.
    private static let theCheck = ["Distribution/verify-private.sh", "Distribution/private-terms.txt"]

    /// The portfolio, with `repositories` made git repositories and `plain` made plain directories, each a path under `root`; `listed` becomes the checkout's own `Distribution/public-names.txt`.
    private static func portfolio(
        in root: URL,
        repositories: [String] = [],
        plain: [String] = [],
        listed: [String] = []
    ) throws -> URL {
        let home = root.appending(path: "Parent/Home")
        for file in theCheck {
            let destination = home.appending(path: file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: repository.appending(path: file), to: destination)
        }
        if !listed.isEmpty {
            try ("# fixture\n" + listed.map { "\($0)  # public\n" }.joined())
                .write(to: home.appending(path: "Distribution/public-names.txt"), atomically: true, encoding: .utf8)
        }
        // The checkout's address is the fixture's own: the gate reads `user.email` off the checkout and turns it into a needle.
        try TestSources.runGit(["init", "-b", "main"], in: home)
        try TestSources.runGit(["config", "user.email", "tester@example.invalid"], in: home)
        for path in ["Parent/Sibling"] + repositories {
            let directory = root.appending(path: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try TestSources.runGit(["init", "-b", "main"], in: directory)
        }
        for path in plain {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }

        return home
    }

    /// Whether the gate, run from `home` with no `GIT_*` variable in its environment, clears a file reading `text`.
    private static func gateClears(_ text: String, in root: URL, invokedAt home: URL) throws -> Bool {
        let document = root.appending(path: "document.txt")
        try text.write(to: document, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [home.appending(path: "Distribution/verify-private.sh").path, document.path]
        process.environment = ProcessEnvironment.withoutGit()
        let sink = Pipe()
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        // Read before waiting, so a run that prints more than a pipe holds cannot deadlock.
        _ = sink.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }

    /// A repository inside a category folder is a project, and a file naming it is a leak.
    @Test
    func aRepositoryInsideACategoryFolderIsLookedFor() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["Puzzles/Gizmo"])

        #expect(try !Self.gateClears("a screenshot taken in Gizmo on launch.\n", in: root, invokedAt: home), "a repository inside a category folder went unlooked-for")
    }

    /// Listing a category folder's word as public clears the word and leaves the projects inside it looked for.
    @Test
    func aCategoryFolderListedAsPublicClearsItsWordAndNotItsMembers() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["Puzzles/Gizmo"], listed: ["puzzles"])

        #expect(try Self.gateClears("a game of Puzzles on the train.\n", in: root, invokedAt: home), "a category word listed as public was taken as private")
        #expect(try !Self.gateClears("a screenshot taken in Gizmo on launch.\n", in: root, invokedAt: home), "listing the category's word cleared its members too")
    }

    /// A folder of repositories keeps its own name: the shape does not tell a category from a product, whose name is the folder's and whose members are roles.
    @Test
    func aProductBesideTheProductFolderKeepsItsNameAndItsRolesAreNotNames() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["Tanager/app", "Tanager/service"])

        #expect(try !Self.gateClears("a screenshot taken in Tanager on launch.\n", in: root, invokedAt: home), "a product folder's own name was dropped")
        #expect(try Self.gateClears("the service restarts on launch.\n", in: root, invokedAt: home), "a product's role was taken as a project name")
    }

    /// A folder holding a plain directory beside a repository is still a category folder: the repository's name and the plain directory's are both looked for.
    @Test
    func aFolderHoldingAPlainDirectoryBesideARepositoryIsEntered() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["Puzzles/Gizmo"], plain: ["Puzzles/Widgetry"])

        #expect(try !Self.gateClears("a screenshot taken in Gizmo on launch.\n", in: root, invokedAt: home), "a plain directory hid the repository beside it")
        #expect(try !Self.gateClears("a screenshot taken in Widgetry on launch.\n", in: root, invokedAt: home), "a plain directory in a category folder went unlooked-for")
        #expect(try !Self.gateClears("a game of Puzzles on the train.\n", in: root, invokedAt: home), "a category folder lost its name")
    }

    /// A folder holding only plain directories is a name and is not entered.
    @Test
    func aFolderHoldingOnlyPlainDirectoriesIsANameAndIsNotEntered() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, plain: ["Puzzles/Widgetry", "Puzzles/Scratchpad"])

        #expect(try !Self.gateClears("a game of Puzzles on the train.\n", in: root, invokedAt: home), "a folder of plain directories lost its name")
        #expect(try Self.gateClears("a screenshot taken in Widgetry on launch.\n", in: root, invokedAt: home), "a folder of plain directories was entered")
    }

    /// A folder set aside by its name is not read at all, members included.
    @Test
    func aFolderSetAsideByItsNameIsNotEntered() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["_Retired/Gizmo"])

        #expect(try Self.gateClears("a screenshot taken in Gizmo on launch.\n", in: root, invokedAt: home), "a set-aside folder was entered")
    }

    /// Beside the checkout nothing is entered: a folder of repositories there is a neighbour, named as before.
    @Test
    func theFirstLevelIsNotEntered() throws {
        let root = try TemporaryDirectory.make("privacy-gate").appending(path: "privacy-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = try Self.portfolio(in: root, repositories: ["Parent/Puzzles/Gizmo"])

        #expect(try !Self.gateClears("a game of Puzzles on the train.\n", in: root, invokedAt: home), "a folder beside the checkout lost its name")
        #expect(try Self.gateClears("a screenshot taken in Gizmo on launch.\n", in: root, invokedAt: home), "a folder beside the checkout was entered")
    }
}
