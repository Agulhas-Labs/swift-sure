//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers that the Claude Code step reports a change when the only thing it did was take out an earlier name's registrations, with a name stood in for the product's (`gizmo`) whose predecessor is `oldone`.
@Suite(.temporaryDirectories)
struct ClaudeInstallStepChangeTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "oldone", displayName: "Oldone")

    private static func step(binary: URL, home: URL) -> ClaudeInstallStep {
        var step = ClaudeInstallStep(
            binary: binary.path,
            environment: ["PATH": binary.deletingLastPathComponent().path, "CFFIXED_USER_HOME": home.path],
            arguments: [binary.path, "install"],
            executable: binary.path,
            runner: QuietRunner(),
            prompt: AllowRunPrompt(isInteractive: false, ask: { _ in nil })
        )
        step.names = [gizmo, older]
        return step
    }

    @Test
    func aRunThatOnlyRemovesTheEarlierRegistrationsCountsAsChanged() throws {
        let home = try TemporaryDirectory.make("install-step-settle-only")
        let binary = try InstallHookBinaryPathTests.executable(at: "bin/gizmo", in: home)
        let servers: [String: Any] = [
            "swift-sure": ["command": binary.path, "args": ["mcp"], "type": "stdio"] as [String: Any],
            "gizmo": ["command": "/opt/bin/gizmo", "args": ["mcp"], "type": "stdio"] as [String: Any],
            "oldone": ["command": "/opt/bin/oldone", "args": ["mcp"], "type": "stdio"] as [String: Any],
        ]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: home.appendingPathComponent(".claude.json"))
        let rules = home.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        try Data("rule".utf8).write(to: rules.appendingPathComponent("oldone.md"))
        try Data("rule".utf8).write(to: rules.appendingPathComponent("gizmo.md"))
        // The first run brings the hooks and the rule current; the earlier server stays in the file the quiet runner never edits.
        _ = try Self.step(binary: binary, home: home).run(output: RecordedOutput().output)
        try Data("rule".utf8).write(to: rules.appendingPathComponent("oldone.md"))

        let report = try Self.step(binary: binary, home: home).run(output: RecordedOutput().output)

        #expect(report.written.isEmpty)
        #expect(report.changed)
    }
}

private extension ClaudeInstallStepChangeTests {
    /// A `claude` that succeeds without changing anything.
    struct QuietRunner: ClaudeMcpRunner {
        func run(_: [String]) throws -> Subprocess.Output? {
            Subprocess.Output(succeeded: true, standardOutput: "done")
        }
    }
}
