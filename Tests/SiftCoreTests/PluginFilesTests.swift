//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers that the committed plugin under `Distribution/plugin/` is what the code generates, so the plugin cannot drift from the installer's registration or from the rule.
///
/// A mismatch prints the expected text in full: that text is the file to commit.
struct PluginFilesTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    private static var pluginRoot: URL {
        repository.appendingPathComponent("Distribution/plugin")
    }

    private static func ruleText() throws -> String {
        try String(contentsOf: repository.appendingPathComponent(ProductName.current.ruleFileName), encoding: .utf8)
    }

    private static func rendered() throws -> [String: String] {
        try PluginFiles.render(rule: ruleText())
    }

    private static func committed(_ path: String) throws -> String {
        try String(contentsOf: pluginRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test
    func everyCommittedFileIsWhatTheRendererWrites() throws {
        let expected = try Self.rendered()
        #expect(expected.count == 4)
        for (path, text) in expected.sorted(by: { $0.key < $1.key }) {
            let actual = try? Self.committed(path)
            #expect(actual == text, "Distribution/plugin/\(path) is not what PluginFiles writes; the file should read exactly:\n\(text)")
        }
    }

    @Test
    func theManifestIsTheOnlyFileInTheManifestDirectory() throws {
        let directory = Self.pluginRoot.appendingPathComponent(".claude-plugin")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        #expect(names == ["plugin.json"])
    }

    @Test
    func theHooksFileNamesEveryEventTheInstallerRegisters() throws {
        let hooks = try Self.hooksByEvent()
        for event in SiftClaudeSetup.events {
            #expect(hooks[event.name] != nil, "hooks.json has no \(event.name) entry")
        }

        #expect(Set(hooks.keys) == Set(SiftClaudeSetup.events.map(\.name)))
    }

    @Test
    func noMatcherNamesTheInstallersToolForm() throws {
        let matchers = try Self.hooksByEvent().values.joined().compactMap { $0["matcher"] as? String }
        #expect(!matchers.isEmpty)
        for matcher in matchers {
            #expect(!matcher.contains(ProductName.current.toolPrefix), "\(matcher) names the form that never fires for a plugin")
        }
        let pre = try #require(Self.hooksByEvent()["PreToolUse"]?.first?["matcher"] as? String)
        #expect(pre.contains(ProductName.pluginToolPrefix + ProductName.current.word + "_" + ProductName.current.pluginServerSegment + "__.*"))
    }

    @Test
    func theSkillBodyIsTheRule() throws {
        let skill = try Self.committed(PluginFiles.skillPath())
        let rule = try Self.ruleText()

        #expect(skill.hasSuffix("\n---\n\n" + PluginFiles.ruleBody(of: rule)))
        #expect(PluginFiles.ruleBody(of: rule).contains("**Prefer"))
        #expect(!PluginFiles.ruleBody(of: rule).hasPrefix("---"))
    }

    @Test
    func theServerRunsTheBinaryWithTheInstallersArguments() throws {
        let file = try Self.json(PluginFiles.serverFilePath)
        let servers = try #require(file["mcpServers"] as? [String: [String: Any]])
        let server = try #require(servers[SiftClaudeSetup.server.name])

        #expect(server["command"] as? String == ProductName.current.binary)
        #expect(server["args"] as? [String] == SiftClaudeSetup.server.arguments)
        #expect(servers.count == 1)
    }

    @Test
    func theSkillDescriptionCarriesTheRunGuidanceForAnAgentThatNeverInvokesIt() throws {
        let skill = try #require(Self.rendered()["skills/\(ProductName.current.word)/SKILL.md"])
        let description = try #require(skill.split(separator: "\n").first { $0.hasPrefix("description: ") })

        #expect(description.contains("\(ProductName.current.binary) run -- "))
        #expect(description.contains("foreground"))
        #expect(description.contains("never piped"))
    }

    @Test
    func theManifestNamesTheProductAndTheVersionTheBinaryReports() throws {
        let manifest = try Self.json(PluginFiles.manifestFilePath)

        #expect(manifest["name"] as? String == ProductName.current.word)
        #expect(manifest["version"] as? String == SiftVersion.current)
    }

    private static func json(_ path: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let data = try Data(committed(path).utf8)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    private static func hooksByEvent(sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: [[String: Any]]] {
        let file = try json(PluginFiles.hooksFilePath, sourceLocation: sourceLocation)
        return try #require(file["hooks"] as? [String: [[String: Any]]], sourceLocation: sourceLocation)
    }
}
