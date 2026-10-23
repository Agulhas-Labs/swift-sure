//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Runs the bundle's real `install.sh` in a fake home and checks that Claude Code's files are written only where Claude Code is found.
@Suite(.temporaryDirectories)
struct InstallScriptClaudeFoundTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Distribution/install.sh")

    /// A bundle holding the script, a `SwiftSure.md`, and a fake `swift-sure` that answers `--version` and appends its arguments to `calls`.
    private static func makeBundle(in directory: URL, calls: URL) throws -> URL {
        let bundle = directory.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: script, to: bundle.appendingPathComponent("install.sh"))
        try "#!/bin/sh\n[ \"${1:-}\" = \"--version\" ] && echo 0.0.0-test\necho \"$*\" >> '\(calls.path)'\nexit 0\n"
            .write(to: bundle.appendingPathComponent("swift-sure"), atomically: true, encoding: .utf8)
        try "rule\n".write(to: bundle.appendingPathComponent("SwiftSure.md"), atomically: true, encoding: .utf8)
        return bundle
    }

    /// A directory holding a fake `claude` that appends its arguments to `calls` and exits 0.
    private static func makeFakeClaude(in directory: URL, calls: URL) throws -> URL {
        let bin = directory.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let claude = bin.appendingPathComponent("claude")
        try "#!/bin/sh\necho \"$*\" >> '\(calls.path)'\nexit 0\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        return bin
    }

    /// Everything the script could write is under `directory`; `CLAUDE_CONFIG_DIR` is left unset unless given and no `GIT_*` variable is passed.
    private static func install(
        in directory: URL, siftCalls: URL, extraPath: URL? = nil, arguments: [String] = [],
        claudeConfigDir: String? = nil
    ) throws -> Run {
        let bundle = try makeBundle(in: directory, calls: siftCalls)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        let destination = directory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [bundle.appendingPathComponent("install.sh").path] + arguments
        var environment = [
            "HOME": home.path,
            "SWIFT_SURE_HOME": directory.appendingPathComponent("state", isDirectory: true).path,
            "SWIFT_SURE_DEST": destination.path,
            "PATH": (extraPath.map { $0.path + ":" } ?? "") + "/usr/bin:/bin",
        ]
        if let claudeConfigDir {
            environment["CLAUDE_CONFIG_DIR"] = claudeConfigDir
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(
            status: process.terminationStatus,
            output: String(bytes: data, encoding: .utf8) ?? "",
            home: home,
            installed: destination.appendingPathComponent("swift-sure")
        )
    }

    private static func calls(in file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    /// With no `claude` on the path and no Claude directory, nothing is written under it, no hook is registered, and the output points to `swift-sure install`.
    @Test
    func noClaudeCodeMeansNothingIsWrittenForIt() throws {
        let directory = try TemporaryDirectory.make("install-claude-absent")
        let calls = directory.appendingPathComponent("sift-calls")

        let run = try Self.install(in: directory, siftCalls: calls)

        #expect(run.status == 0, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: run.home.appendingPathComponent(".claude").path))
        #expect(run.output.contains("swift-sure install"))
        #expect(run.output.contains("re-run install.sh"))
        #expect(!Self.calls(in: calls).contains("install-hook"))
        #expect(FileManager.default.isExecutableFile(atPath: run.installed.path))
    }

    /// An existing Claude directory counts as found: the rule is written and the hooks are registered.
    @Test
    func anExistingClaudeDirectoryIsFound() throws {
        let directory = try TemporaryDirectory.make("install-claude-directory")
        let calls = directory.appendingPathComponent("sift-calls")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("home/.claude", isDirectory: true), withIntermediateDirectories: true
        )

        let run = try Self.install(in: directory, siftCalls: calls)

        #expect(run.status == 0, "\(run.output)")
        #expect(FileManager.default.fileExists(atPath: run.home.appendingPathComponent(".claude/rules/swift-sure.md").path))
        #expect(Self.calls(in: calls).contains("install-hook"))
    }

    /// A set configuration directory that exists counts as found with no home Claude directory, and the rule lands under it, not under the home.
    @Test
    func anExistingConfigDirectoryIsFoundAndHoldsTheRule() throws {
        let directory = try TemporaryDirectory.make("install-claude-config-dir")
        let calls = directory.appendingPathComponent("sift-calls")
        let config = directory.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let run = try Self.install(in: directory, siftCalls: calls, claudeConfigDir: config.path)

        #expect(run.status == 0, "\(run.output)")
        #expect(FileManager.default.fileExists(atPath: config.appendingPathComponent("rules/swift-sure.md").path))
        #expect(!FileManager.default.fileExists(atPath: run.home.appendingPathComponent(".claude").path))
        #expect(Self.calls(in: calls).contains("install-hook"))
    }

    /// A set configuration directory that is missing is not found even when the home Claude directory exists, and nothing is written.
    @Test
    func aMissingConfigDirectoryIsNotFound() throws {
        let directory = try TemporaryDirectory.make("install-claude-config-missing")
        let calls = directory.appendingPathComponent("sift-calls")
        let home = directory.appendingPathComponent("home/.claude", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let missing = directory.appendingPathComponent("missing")

        let run = try Self.install(in: directory, siftCalls: calls, claudeConfigDir: missing.path)

        #expect(run.status == 0, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("rules").path))
        #expect(!Self.calls(in: calls).contains("install-hook"))
    }

    /// An empty configuration directory variable counts as unset: the home Claude directory decides and holds the rule.
    @Test
    func anEmptyConfigDirectoryFallsBackToTheHomeDirectory() throws {
        let directory = try TemporaryDirectory.make("install-claude-config-empty")
        let calls = directory.appendingPathComponent("sift-calls")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("home/.claude", isDirectory: true), withIntermediateDirectories: true
        )

        let run = try Self.install(in: directory, siftCalls: calls, claudeConfigDir: "")

        #expect(run.status == 0, "\(run.output)")
        #expect(FileManager.default.fileExists(atPath: run.home.appendingPathComponent(".claude/rules/swift-sure.md").path))
        #expect(Self.calls(in: calls).contains("install-hook"))
    }

    /// A `claude` on the path counts as found with no Claude directory: the hooks are registered and the server is added through it.
    @Test
    func claudeOnThePathIsFound() throws {
        let directory = try TemporaryDirectory.make("install-claude-path")
        let calls = directory.appendingPathComponent("sift-calls")
        let claudeCalls = directory.appendingPathComponent("claude-calls")
        let bin = try Self.makeFakeClaude(in: directory, calls: claudeCalls)

        let run = try Self.install(in: directory, siftCalls: calls, extraPath: bin)

        #expect(run.status == 0, "\(run.output)")
        #expect(Self.calls(in: calls).contains("install-hook"))
        #expect(Self.calls(in: claudeCalls).contains("mcp add"))
    }

    /// An allow-rule flag where Claude Code is not found is reported as ignored.
    @Test
    func anAllowFlagIsIgnoredWithoutClaudeCode() throws {
        let directory = try TemporaryDirectory.make("install-claude-flag")
        let calls = directory.appendingPathComponent("sift-calls")

        let run = try Self.install(in: directory, siftCalls: calls, arguments: ["--allow-run"])

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("--allow-run applies only to Claude Code and was ignored"))
        #expect(!Self.calls(in: calls).contains("install-hook"))
    }
}

extension InstallScriptClaudeFoundTests {
    private struct Run {
        var status: Int32
        var output: String
        var home: URL
        var installed: URL
    }
}
