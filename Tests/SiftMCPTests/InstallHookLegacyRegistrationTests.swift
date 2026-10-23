//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// Covers what `install-hook` takes out of an earlier release's registrations and how it names the binary, with a name stood in for the product's (`gizmo`) whose predecessor is `swift-sure`.
@Suite(.temporaryDirectories)
struct InstallHookLegacyRegistrationTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")
    private static let older = ProductName(word: "swift-sure", displayName: "SwiftSure")
    private static let names = [gizmo, older]

    /// The install run in `home` with the current name's server and rule in place beside the user config `servers` registers, answering what was asked of `claude` and what was printed.
    private static func install(in home: URL, servers: [String: Any], rule: Bool = true) throws -> (asked: [(ProductName, SiftUninstall.ServerScope)], printed: String) {
        let current: [String: Any] = ["command": "/opt/bin/gizmo", "args": ["mcp"], "type": "stdio"]
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers.merging(["gizmo": current]) { first, _ in first }]).write(to: home.appendingPathComponent(".claude.json"))
        let rules = home.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        try Data("rule".utf8).write(to: rules.appendingPathComponent("gizmo.md"))
        if rule {
            try Data("rule".utf8).write(to: rules.appendingPathComponent("swift-sure.md"))
        }
        let binary = try InstallHookBinaryPathTests.executable(at: "bin/gizmo", in: home)
        var command = try InstallHookCommand.parse(["--no-allow-run"])
        let recorded = RecordedOutput()
        let asked = Asked()
        command.output = recorded.output
        command.names = names
        command.arguments = [binary.path, "install-hook"]
        command.environment = ["PATH": binary.deletingLastPathComponent().path, "CFFIXED_USER_HOME": home.path]
        command.executable = binary.path
        command.stateDirectory = home.appendingPathComponent("state")
        command.runPlugin = { _, _ in .noClaude }
        command.removeLegacyServer = { _, name, scope in
            asked.calls.append((name, scope))
            return .removed
        }
        try command.run()
        return (asked.calls, recorded.printed)
    }

    @Test
    func installRemovesTheServerAndTheRuleAnEarlierReleaseRegistered() throws {
        let home = try TemporaryDirectory.make("install-legacy")
        let entry: [String: Any] = ["command": "/opt/bin/swift-sure", "args": ["mcp"], "type": "stdio"]

        let result = try Self.install(in: home, servers: ["swift-sure": entry])

        #expect(result.asked.map(\.0) == [Self.older])
        #expect(result.asked.first?.1 == .user)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/rules/swift-sure.md").path))
        #expect(result.printed.contains("rule: removed"))
    }

    @Test
    func installLeavesAServerOfTheOlderNameThatRunsSomethingElse() throws {
        let home = try TemporaryDirectory.make("install-legacy-foreign")
        let entry: [String: Any] = ["command": "/opt/bin/other-tool", "args": ["serve"], "type": "stdio"]

        let result = try Self.install(in: home, servers: ["swift-sure": entry], rule: false)

        #expect(result.asked.isEmpty)
    }

    @Test
    func aBinaryWhoseNameIsNotAnEarlierNameIsRegisteredAsItIs() throws {
        let scratch = try TemporaryDirectory.make("install-sibling")
        let invoked = try InstallHookBinaryPathTests.executable(at: "opt/sift-dev", in: scratch)
        _ = try InstallHookBinaryPathTests.executable(at: "opt/gizmo", in: scratch)
        let environment = ["PATH": invoked.deletingLastPathComponent().path, "CFFIXED_USER_HOME": scratch.path]

        let path = InstallHookCommand.binaryPath(invokedAs: invoked.path, environment: environment, executable: invoked.path, names: Self.names)

        #expect(path == invoked.path)
    }
}

extension InstallHookLegacyRegistrationTests {
    private final class Asked: @unchecked Sendable {
        var calls: [(ProductName, SiftUninstall.ServerScope)] = []
    }
}
