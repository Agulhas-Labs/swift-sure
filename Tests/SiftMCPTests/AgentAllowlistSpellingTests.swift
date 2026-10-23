//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Covers that the allowlist advice suggests the spelling the list already uses.
@Suite(.temporaryDirectories)
struct AgentAllowlistSpellingTests {
    private static func report(frontmatter: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let base = try TemporaryDirectory.make("allowlist-spelling")
        let home = base.appendingPathComponent("home", isDirectory: true)
        let agents = home.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let body = (["---"] + frontmatter + ["---", "", "You do the thing."]).joined(separator: "\n")
        try Data(body.utf8).write(to: agents.appendingPathComponent("worker.md"))
        return try #require(AgentAllowlistReport.text(root: nil, home: home), sourceLocation: sourceLocation)
    }

    @Test
    func aPluginSpelledListIsGivenThePluginNames() throws {
        let text = try Self.report(frontmatter: ["name: worker", "tools: Read, mcp__plugin_acme_other__lookup"])

        #expect(text.contains(IndexToolName.pluginQualified.joined(separator: ", ")))
        #expect(!text.contains(IndexToolName.qualified.joined(separator: ", ")))
        #expect(IndexToolName.pluginQualified.first?.hasPrefix("mcp__plugin_") == true)
    }

    @Test
    func aPlainListIsGivenThePlainNames() throws {
        let text = try Self.report(frontmatter: ["name: worker", "tools: Read, Grep"])

        #expect(text.contains(IndexToolName.qualified.joined(separator: ", ")))
        #expect(!text.contains(IndexToolName.pluginQualified.joined(separator: ", ")))
    }

    @Test
    func thePluginNamesAreReadAsThisServersTools() {
        #expect(IndexToolName.pluginQualified.allSatisfy { IndexToolName.tool(named: $0) != nil })
        #expect(IndexToolName.pluginQualified.count == IndexToolName.qualified.count)
    }
}
