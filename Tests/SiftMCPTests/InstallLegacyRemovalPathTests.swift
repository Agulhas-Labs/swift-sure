//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers when and through whom an install takes out what an earlier release registered, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct InstallLegacyRemovalPathTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]
    private static let reversed = [older, gizmo]

    /// Seeds the home with both names' servers and rules.
    private static func seed(_ home: URL) throws {
        let servers: [String: Any] = [
            "swift-sure": ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"] as [String: Any],
            "gizmo": ["command": "/opt/bin/gizmo", "args": ["mcp"], "type": "stdio"] as [String: Any],
        ]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: home.appendingPathComponent(".claude.json"))
        let rules = home.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        try Data("rule".utf8).write(to: rules.appendingPathComponent("swift-sure.md"))
        try Data("rule".utf8).write(to: rules.appendingPathComponent("gizmo.md"))
    }

    @Test
    func anUnreadableSettingsFileLeavesTheEarlierRegistrationsInPlace() throws {
        let home = try TemporaryDirectory.make("install-unreadable-settings")
        try Self.seed(home)
        let settings = home.appendingPathComponent(".claude/settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path) }
        let binary = try InstallHookBinaryPathTests.executable(at: "bin/gizmo", in: home)
        var command = try InstallHookCommand.parse(["--no-allow-run"])
        let asked = Asked()
        command.output = RecordedOutput().output
        command.names = Self.names
        command.arguments = [binary.path, "install-hook"]
        command.environment = ["PATH": binary.deletingLastPathComponent().path, "CFFIXED_USER_HOME": home.path]
        command.executable = binary.path
        command.stateDirectory = home.appendingPathComponent("state")
        command.runPlugin = { _, _ in .noClaude }
        command.removeLegacyServer = { _, name, _ in
            asked.names.append(name)
            return .removed
        }

        #expect(throws: SettingsFile.Refused.self) { try command.install() }

        #expect(asked.names.isEmpty)
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/rules/swift-sure.md").path))
    }

    @Test
    func theInstallStepRemovesTheEarlierServerThroughItsOwnRunner() throws {
        let home = try TemporaryDirectory.make("install-step-runner")
        try Self.seed(home)
        let binary = try InstallHookBinaryPathTests.executable(at: "bin/swift-sure", in: home)
        let runner = RecordingRunner()
        var step = ClaudeInstallStep(
            binary: binary.path,
            environment: ["PATH": binary.deletingLastPathComponent().path, "CFFIXED_USER_HOME": home.path],
            arguments: [binary.path, "install"],
            executable: binary.path,
            runner: runner,
            prompt: AllowRunPrompt(isInteractive: false, ask: { _ in nil })
        )
        step.names = Self.reversed

        _ = try step.run(output: RecordedOutput().output)

        #expect(runner.calls.contains(SiftUninstall.ServerScope.user.removalArguments(for: Self.gizmo)))
    }
}

private extension InstallLegacyRemovalPathTests {
    final class Asked: @unchecked Sendable {
        var names: [ProductName] = []
    }

    /// A `claude` that records every run and succeeds without changing anything.
    final class RecordingRunner: ClaudeMcpRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [[String]] = []

        var calls: [[String]] {
            lock.withLock { recorded }
        }

        func run(_ arguments: [String]) throws -> Subprocess.Output? {
            lock.withLock { recorded.append(arguments) }
            return Subprocess.Output(succeeded: true, standardOutput: "done")
        }
    }
}
