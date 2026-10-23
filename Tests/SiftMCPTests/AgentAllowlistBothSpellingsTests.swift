//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Covers that the allowlist advice names the agents each tool line is for when both spellings are printed.
@Suite(.temporaryDirectories)
struct AgentAllowlistBothSpellingsTests {
    private static func report(_ agents: [(name: String, tools: String)], sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let base = try TemporaryDirectory.make("allowlist-both-spellings")
        let home = base.appendingPathComponent("home", isDirectory: true)
        let directory = home.appendingPathComponent(".claude/agents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for agent in agents {
            let body = ["---", "name: \(agent.name)", "tools: \(agent.tools)", "---", "", "You do the thing."].joined(separator: "\n")
            try Data(body.utf8).write(to: directory.appendingPathComponent("\(agent.name).md"))
        }
        return try #require(AgentAllowlistReport.text(root: nil, home: home), sourceLocation: sourceLocation)
    }

    @Test
    func eachLineNamesTheAgentsItIsFor() throws {
        let text = try Self.report([("plainer", "Read, Grep"), ("pluggy", "Read, mcp__plugin_acme_other__lookup")])

        #expect(text.contains("for plainer: \(IndexToolName.qualified.joined(separator: ", "))"))
        #expect(text.contains("for pluggy: \(IndexToolName.pluginQualified.joined(separator: ", "))"))
    }

    @Test
    func aSingleLineIsNotPrefixed() throws {
        let text = try Self.report([("plainer", "Read, Grep")])

        #expect(!text.contains("for plainer:"))
        #expect(text.contains("      \(IndexToolName.qualified.joined(separator: ", "))"))
    }
}
