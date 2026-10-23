//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A lookup aimed at a Swift tree is answered from that tree's index, so a Swift-free working directory does not silence it.
@Suite(.temporaryDirectories)
struct SwiftFreeReachedTreeTests {
    private static func repository(named name: String, files: [String: String]) throws -> URL {
        let root = try TemporaryDirectory.make(name).appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-b", "main"], ["add", "-A"], ["commit", "-m", "seed"]] {
            try MCPTestRepo.run(git: arguments, in: root)
        }
        return root.resolvingSymlinksInPath()
    }

    private static func swiftFree() throws -> URL {
        try repository(named: "reach-free", files: ["notes.md": "# Notes\n"])
    }

    private static func swiftRepository() throws -> URL {
        let members = (1 ... 400).map { "    func member\($0)() -> Int { \($0) }" }.joined(separator: "\n")
        return try repository(named: "reach-swift", files: [
            "Package.swift": "// swift-tools-version: 6.0\n",
            "Sources/Kit/Big.swift": "struct Big {\n" + members + "\n}\n",
        ])
    }

    private static func lookup(_ payload: [String: Any], command: String? = nil, in root: URL) throws -> PreToolUseCommand.Lookup? {
        try PreToolUseCommand.lookup(
            command: command,
            payload: payload,
            in: root.path,
            noting: SuppressionLog(fileURL: TemporaryDirectory.make("ignored").appendingPathComponent("ignored.jsonl")),
            couldAnswer: { _, _ in true }
        )
    }

    @Test
    func aToolchainRunAfterACdIntoASwiftRepositoryIsAdvisedFromASwiftFreeDirectory() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        #expect(try Self.lookup([:], command: "swift test", in: free) == nil)
        #expect(try Self.lookup([:], command: "cd \(swift.path) && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "(cd \(swift.path) && swift test)", in: free) != nil)
        #expect(try Self.lookup([:], command: "cd \(swift.path); swift build", in: free) != nil)
    }

    @Test
    func aPackagePathIntoASwiftRepositoryIsAdvisedFromASwiftFreeDirectory() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        #expect(try Self.lookup([:], command: "swift test --package-path \(swift.path)", in: free) != nil)
        #expect(try Self.lookup([:], command: "swift test --package-path=\(swift.path)", in: free) != nil)
    }

    @Test
    func aCdTargetThatNamesNoDirectoryHereCountsAsSwiftPresent() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        #expect(try Self.lookup([:], command: "PKG=\(swift.path); cd \"$PKG\" && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "cd - && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "cd nowhere && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "swift test --package-path missing", in: free) != nil)
    }

    @Test
    func aCdReadPastItsOptionsOrInsideABraceGroupReachesItsTarget() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        #expect(try Self.lookup([:], command: "cd -P \(swift.path) && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "cd -- \(swift.path) && swift test", in: free) != nil)
        #expect(try Self.lookup([:], command: "{ cd \(swift.path); swift test; }", in: free) != nil)
        #expect(RunAdvice.reachedPaths(of: "cd -P -L -- /w/kit && swift test") == ["/w/kit"])
        #expect(RunAdvice.reachedPaths(of: "{ cd /w/kit; swift test; }") == ["/w/kit"])
    }

    @Test
    func aSwiftPMChdirIntoASwiftRepositoryIsAdvisedFromASwiftFreeDirectory() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        #expect(try Self.lookup([:], command: "swift build -C \(swift.path)", in: free) != nil)
        #expect(try Self.lookup([:], command: "swift test --chdir \(swift.path)", in: free) != nil)
        #expect(try Self.lookup([:], command: "swift build --chdir=\(swift.path)", in: free) != nil)
        #expect(RunAdvice.reachedPaths(of: "swift run -C /w/kit") == ["/w/kit"])
        #expect(RunAdvice.reachedPaths(of: "make -C /w/kit && swift build") == [])
    }

    /// The second target is relative to the first, so read against the caller it names nothing there, and it must not fall back to the caller's own Swift-free directory: `Pods` is left out of the caller's walk, while the package inside it is a repository of its own.
    @Test
    func aCdRelativeToAnEarlierCdCountsAsSwiftPresent() throws {
        let free = try Self.repository(named: "reach-pods", files: ["notes.md": "# Notes\n", "Pods/Kit/Package.swift": "// swift-tools-version: 6.0\n"])
        try MCPTestRepo.run(git: ["init", "-b", "main"], in: free.appendingPathComponent("Pods/Kit"))

        #expect(try Self.lookup([:], command: "swift test", in: free) == nil)
        #expect(try Self.lookup([:], command: "cd Pods && cd Kit && swift test", in: free) != nil)
    }

    /// An Xcode project outside git reaches the directory holding it, where its sources are, and not the bundle, which holds none.
    @Test
    func anXcodeProjectReachesTheDirectoryHoldingIt() throws {
        let free = try Self.swiftFree()
        let app = try TemporaryDirectory.make("reach-nogit").appendingPathComponent("app").resolvingSymlinksInPath()
        for (path, text) in ["A.xcodeproj/project.pbxproj": "// !$*UTF8*$!\n", "Sources/V.swift": "struct V {}\n"] {
            let file = app.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        let project = app.appendingPathComponent("A.xcodeproj").path

        #expect(try Self.lookup([:], command: "xcodebuild -project \(project) -scheme A build", in: free) != nil)
        #expect(RunAdvice.reachedPaths(of: "xcodebuild -workspace App.xcworkspace -scheme A build") == ["."])
    }

    @Test
    func aWholeReadOfASwiftFileByAbsolutePathIsAnsweredFromASwiftFreeDirectory() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()
        let big = swift.appendingPathComponent("Sources/Kit/Big.swift").path

        let read = try Self.lookup(["tool_name": "Read", "tool_input": ["file_path": big]], in: free)

        #expect(read?.inPlace != nil)
    }

    @Test
    func aShellReadAfterACdIntoASwiftRepositoryIsAnsweredFromASwiftFreeDirectory() throws {
        let free = try Self.swiftFree()
        let swift = try Self.swiftRepository()

        let shell = try Self.lookup([:], command: "cd \(swift.path)/Sources/Kit && cat Big.swift", in: free)

        #expect(shell != nil)
    }

    @Test
    func aRepositoryWhoseOnlySwiftIsInAPackageBundleOrVendorIsNotSilenced() throws {
        let bundle = try Self.repository(named: "reach-bundle", files: ["App.swiftpm/Sources/Main.swift": "struct Main {}\n"])
        let vendored = try Self.repository(named: "reach-vendor", files: ["vendor/X.swift": "struct X {}\n"])

        #expect(!SwiftTree.holdsNoSwift(inRepositoryOf: bundle.path))
        #expect(!SwiftTree.holdsNoSwift(inRepositoryOf: bundle.appendingPathComponent("App.swiftpm").path))
        #expect(!SwiftTree.holdsNoSwift(inRepositoryOf: vendored.path))
    }
}
