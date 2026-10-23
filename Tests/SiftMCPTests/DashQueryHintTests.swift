//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A lookup whose single argument starts with a dash is read as an option; the usage error says how to search for it.
@Suite(.temporaryDirectories)
struct DashQueryHintTests {
    // MARK: - The line

    @Test
    func eachLookupSubcommandGivesItsLine() {
        #expect(DashQueryHint.line(for: ["strings", "--root"]) == "--root was read as an option; to search for it, put -- first: swift-sure strings -- \"--root\"")
        #expect(DashQueryHint.line(for: ["search", "--x"]) == "--x was read as an option; to search for it, put -- first: swift-sure search -- \"--x\"")
        #expect(DashQueryHint.line(for: ["where", "--root"]) == "--root was read as an option; to look it up, put -- first: swift-sure where -- \"--root\"")
        #expect(DashQueryHint.line(for: ["digest", "-v"]) == "-v was read as an option; to look it up, put -- first: swift-sure digest -- \"-v\"")
    }

    @Test
    func anyOtherShapeGivesNone() {
        let shapes: [[String]] = [
            ["where", "--refs", "--files"],
            ["strings", "foo", "--root"],
            ["strings", "--root", "/x"],
            ["strings", "--", "--root"],
            ["strings", "--help"],
            ["strings", "-h"],
            ["strings", "-"],
            ["strings", "foo"],
            ["strings"],
            ["run", "--root"],
        ]
        for shape in shapes {
            #expect(DashQueryHint.line(for: shape) == nil, "\(shape)")
        }
    }

    // MARK: - The binary

    @Test
    func theUsageErrorEndsWithTheHintAndTheDashedFormSearches() throws {
        let directory = try TemporaryDirectory.make("dash-hint")
        defer { try? FileManager.default.removeItem(at: directory) }

        let refused = try Self.sift(["strings", "--root"], in: directory)
        #expect(refused.status == 64)
        #expect(refused.output.split(separator: "\n").last.map(String.init) == "--root was read as an option; to search for it, put -- first: swift-sure strings -- \"--root\"")

        let repository = try Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let searched = try Self.sift(["strings", "--", "--root"], in: repository)
        #expect(searched.status == 0, "\(searched.output)")
    }
}

private extension DashQueryHintTests {
    static func sift(_ arguments: [String], in directory: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> (status: Int32, output: String) {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle, at \(BuiltExecutable.expected.path)", sourceLocation: sourceLocation)
        return try spawn(binary.path, arguments, in: directory, isolated: true)
    }

    /// One process in `directory`, with no git variables; an isolated one also gets its own home and an empty Claude config directory.
    static func spawn(_ executable: String, _ arguments: [String], in directory: URL, isolated: Bool) throws -> (status: Int32, output: String) {
        let home = try TemporaryDirectory.make("dash-hint-home")
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessEnvironment.withoutGit()
        if isolated {
            environment[RunLedger.switchName] = nil
            environment["SWIFT_SURE_HOME"] = home.path
            environment["CLAUDE_CONFIG_DIR"] = home.path
            environment["CLAUDE_CODE_SESSION_ID"] = nil
        }
        process.environment = environment
        let sink = Pipe()
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        let output = sink.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
    }

    /// A disposable, freshly committed repository.
    static func makeRepository(sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let root = try TemporaryDirectory.make("dash-hint-repo")
        try "seed\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        for arguments in [
            ["init", "-b", "main"],
            ["config", "user.email", "test@example.com"],
            ["config", "user.name", "Tester"],
            ["add", "-A"],
            ["commit", "-m", "seed"],
        ] {
            let result = try spawn("/usr/bin/git", arguments, in: root, isolated: false)
            #expect(result.status == 0, "\(arguments.joined(separator: " ")): \(result.output)", sourceLocation: sourceLocation)
        }
        return root
    }
}
