//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Runs the bundle's real `install.sh` with a fake binary and a fake `claude`: by default it is the full set; with `--run-only` it is run mode (no rule, no `mcp add`, the server removed).
@Suite(.temporaryDirectories)
struct InstallScriptRunModeTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Distribution/install.sh")

    private static func executable(_ text: String, at url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Runs the script with `arguments` in a fresh fake home; `seed` runs after the home exists, before the script.
    private static func run(_ arguments: [String], claudeExit: Int = 0, withClaude: Bool = true, seed: (URL) throws -> Void = { _ in }) throws -> Run {
        let directory = try TemporaryDirectory.make("install-run-mode")
        let log = directory.appendingPathComponent("calls")
        let bundle = directory.appendingPathComponent("bundle", isDirectory: true)
        let bin = directory.appendingPathComponent("fake-bin", isDirectory: true)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        let config = directory.appendingPathComponent("claude-config", isDirectory: true)
        for folder in [bundle, bin, home, config] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(at: script, to: bundle.appendingPathComponent("install.sh"))
        try "rule\n".write(to: bundle.appendingPathComponent("SwiftSure.md"), atomically: true, encoding: .utf8)
        try executable("#!/bin/sh\n[ \"${1:-}\" = \"--version\" ] && echo 0.0.0-test\necho \"binary $*\" >> '\(log.path)'\nexit 0\n", at: bundle.appendingPathComponent("swift-sure"))
        if withClaude {
            try executable("#!/bin/sh\necho \"claude $*\" >> '\(log.path)'\nexit \(claudeExit)\n", at: bin.appendingPathComponent("claude"))
        }
        try seed(config)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [bundle.appendingPathComponent("install.sh").path] + arguments
        process.environment = [
            "HOME": home.path,
            "CLAUDE_CONFIG_DIR": config.path,
            "SWIFT_SURE_HOME": directory.appendingPathComponent("state", isDirectory: true).path,
            "SWIFT_SURE_DEST": directory.appendingPathComponent("dest", isDirectory: true).path,
            "PATH": bin.path + ":/usr/bin:/bin",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        let calls = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        return Run(status: process.terminationStatus, output: output, calls: calls, rule: config.appendingPathComponent("rules/swift-sure.md"))
    }

    @Test
    func runOnlyCopiesNoRuleAddsNoServerAndTheFlagsReachInstallHook() throws {
        let run = try Self.run(["--run-only", "--allow-run"])

        #expect(run.status == 0, "\(run.output)")
        #expect(!FileManager.default.fileExists(atPath: run.rule.path))
        #expect(!run.calls.contains { $0.hasPrefix("claude mcp add") }, "\(run.calls)")
        #expect(run.calls.contains("claude mcp remove swift-sure --scope user"), "\(run.calls)")
        #expect(run.calls.contains("binary install-hook --run-only --allow-run"), "\(run.calls)")
        #expect(run.output.contains("Mode: run-only"), "\(run.output)")
        #expect(run.output.contains("the previous registration was removed"), "\(run.output)")
    }

    @Test
    func runOnlyRemovesARuleAnEarlierInstallCopiedAndKeepsASymlink() throws {
        let copied = try Self.run(["--run-only"]) { config in
            try FileManager.default.createDirectory(at: config.appendingPathComponent("rules"), withIntermediateDirectories: true)
            try "old\n".write(to: config.appendingPathComponent("rules/swift-sure.md"), atomically: true, encoding: .utf8)
        }
        #expect(copied.status == 0, "\(copied.output)")
        #expect(!FileManager.default.fileExists(atPath: copied.rule.path))

        let linked = try Self.run(["--run-only"]) { config in
            try FileManager.default.createDirectory(at: config.appendingPathComponent("rules"), withIntermediateDirectories: true)
            let target = config.deletingLastPathComponent().appendingPathComponent("checkout.md")
            try "checkout\n".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: config.appendingPathComponent("rules/swift-sure.md"), withDestinationURL: target)
        }
        #expect(linked.status == 0, "\(linked.output)")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linked.rule.path)) != nil)
    }

    @Test
    func byDefaultTheRuleIsCopiedTheServerIsAddedAndInstallHookGetsNoModeFlag() throws {
        let run = try Self.run([])

        #expect(run.status == 0, "\(run.output)")
        #expect(FileManager.default.fileExists(atPath: run.rule.path))
        #expect(run.calls.contains { $0.hasPrefix("claude mcp add") }, "\(run.calls)")
        #expect(run.calls.contains("binary install-hook"), "\(run.calls)")
        #expect(run.output.contains("Mode: index"), "\(run.output)")
    }

    @Test
    func runOnlyWithAFailingMcpRemoveDoesNotClaimTheRegistrationWasRemoved() throws {
        let run = try Self.run(["--run-only"], claudeExit: 1)

        #expect(run.status == 0, "\(run.output)")
        #expect(!run.output.contains("was removed"), "\(run.output)")
        #expect(run.output.contains("could not be confirmed gone"), "\(run.output)")
    }

    @Test
    func runOnlyWhereClaudeIsFoundOnlyByDirectoryPrintsTheManualRemoveCommand() throws {
        let run = try Self.run(["--run-only"], withClaude: false)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.calls.filter { $0.hasPrefix("claude") }.isEmpty, "\(run.calls)")
        #expect(run.output.contains("claude mcp remove swift-sure --scope user"), "\(run.output)")
    }

    @Test
    func allowLookupsWithRunOnlyExitsTwoBeforeWritingAnything() throws {
        let run = try Self.run(["--run-only", "--allow-lookups"])

        #expect(run.status == 2, "\(run.output)")
        #expect(run.output.contains("--allow-lookups") && run.output.contains("--run-only"))
        #expect(run.calls.isEmpty, "\(run.calls)")
        #expect(!run.output.contains("installed:"), "\(run.output)")
    }
}

extension InstallScriptRunModeTests {
    private struct Run {
        let status: Int32
        let output: String
        let calls: [String]
        let rule: URL
    }
}
