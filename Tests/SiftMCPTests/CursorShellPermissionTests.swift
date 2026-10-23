//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Cursor's shell permission files read into the patterns the build rewrite is judged against: each entry form, the global file beside a project's, and a file that cannot be read.
@Suite(.temporaryDirectories)
struct CursorShellPermissionTests {
    /// Each entry form gives the patterns Cursor's own matching implies, an entry for another tool gives none, and a malformed shell entry does not parse.
    @Test(arguments: [
        ("Shell", ["*"]),
        ("Shell(*)", ["*"]),
        ("Shell(swift)", ["swift", "swift *"]),
        ("Shell(swift:*)", ["swift", "swift *"]),
        ("Shell(swift:test *)", ["swift test *"]),
        ("Read(**/*.swift)", []),
        ("Write(src/**)", []),
    ])
    func eachEntryFormGivesItsPatterns(entry: String, patterns: [String]) {
        #expect(CursorShellPermission.patterns(of: entry) == patterns)
    }

    /// A shell entry with no closing parenthesis, an empty body, or an empty command or argument glob does not parse.
    @Test(arguments: ["Shell(swift", "Shell()", "Shell(:test)", "Shell(swift:)"])
    func aMalformedShellEntryDoesNotParse(entry: String) {
        #expect(CursorShellPermission.patterns(of: entry) == nil)
    }

    /// The global file's rules and the project file's are read together, deny entries as vetoes and allow entries as allowed.
    @Test
    func theGlobalAndProjectFilesAreReadTogether() throws {
        let scene = try Scene()
        try scene.write(#"{"permissions": {"allow": ["Shell(git)", "Read(a)"], "deny": ["Shell(rm:-rf *)"]}}"#, to: scene.global)
        try scene.write(#"{"permissions": {"allow": ["Shell(swift:test *)"], "deny": ["Shell(curl)"]}}"#, to: scene.project(scene.repo))

        let permission = scene.load(from: scene.repo)

        #expect(permission.allowed == ["git", "git *", "swift test *"])
        #expect(permission.vetoed == ["rm -rf *", "curl", "curl *"])
        #expect(!permission.hasUnreadableSettings)
    }

    /// A command run below the repository's top level reads the project file there as well as the one in its own directory.
    @Test
    func aSubdirectoryReadsTheRepositoryTopLevelFileToo() throws {
        let scene = try Scene()
        let nested = scene.repo.appendingPathComponent("Packages/Core")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try scene.write(#"{"permissions": {"deny": ["Shell(swift)"]}}"#, to: scene.project(scene.repo))
        try scene.write(#"{"permissions": {"allow": ["Shell(swift-sure)"]}}"#, to: scene.project(nested))

        let permission = scene.load(from: nested)

        #expect(permission.allowed == ["swift-sure", "swift-sure *"])
        #expect(permission.vetoed == ["swift", "swift *"])
    }

    /// Missing files are no rules, and an object with no permissions is none either.
    @Test
    func missingFilesAreNoRules() throws {
        let scene = try Scene()
        #expect(scene.load(from: scene.repo) == WrappedRunPermission(allowed: [], vetoed: []))

        try scene.write(#"{"version": 1}"#, to: scene.project(scene.repo))
        #expect(scene.load(from: scene.repo) == WrappedRunPermission(allowed: [], vetoed: []))
    }

    /// A file that is there but cannot be read as Cursor's rules marks the reading unreadable, whichever of the files it is.
    @Test(arguments: [
        "not json {",
        "[]",
        #"{"permissions": []}"#,
        #"{"permissions": {"allow": "Shell(swift)"}}"#,
        #"{"permissions": {"deny": [3]}}"#,
        #"{"permissions": {"deny": ["Shell(swift"]}}"#,
    ])
    func anUnreadableFileWithholdsEveryRewrite(contents: String) throws {
        let scene = try Scene()
        try scene.write(contents, to: scene.project(scene.repo))
        #expect(scene.load(from: scene.repo).hasUnreadableSettings)

        let other = try Scene()
        try other.write(contents, to: other.global)
        #expect(other.load(from: other.repo).hasUnreadableSettings)
    }

    /// The rewrite adds no new prompt where nothing allows the build as written, or where something allows the wrapping too; it does where only the build as written is allowed.
    @Test
    func theRewriteAddsAPromptOnlyWhereTheBuildAsWrittenWasAllowed() {
        let legs = ["swift-sure run -- swift test"]

        #expect(CursorShellPermission.addsNoNewPrompt(WrappedRunPermission(allowed: [], vetoed: []), legs: legs))
        #expect(!CursorShellPermission.addsNoNewPrompt(WrappedRunPermission(allowed: ["swift", "swift *"], vetoed: []), legs: legs))
        #expect(CursorShellPermission.addsNoNewPrompt(WrappedRunPermission(allowed: ["swift", "swift *", "swift-sure", "swift-sure *"], vetoed: []), legs: legs))
        #expect(CursorShellPermission.addsNoNewPrompt(WrappedRunPermission(allowed: ["git", "git *"], vetoed: []), legs: legs))
    }
}

extension CursorShellPermissionTests {
    /// A git repository and a home of the test's own, so no real Cursor configuration is ever read.
    struct Scene {
        let repo: URL
        let home: URL

        init() throws {
            repo = try TemporaryDirectory.make("cursor-rules-repo")
            home = try TemporaryDirectory.make("cursor-rules-home")
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["init", "-q", repo.path]
            git.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
            try git.run()
            git.waitUntilExit()
        }

        /// The global rules file under this scene's home.
        var global: URL {
            home.appendingPathComponent(".cursor/cli-config.json")
        }

        /// The project rules file in `directory`.
        func project(_ directory: URL) -> URL {
            directory.appendingPathComponent(".cursor/cli.json")
        }

        /// Writes `contents` to `file`, making its directory first.
        func write(_ contents: String, to file: URL) throws {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }

        /// Cursor's rules for a command run from `directory`, under this scene's home.
        func load(from directory: URL) -> WrappedRunPermission {
            CursorShellPermission.load(directory: directory.path, environment: ["HOME": home.path])
        }
    }
}
