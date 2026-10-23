//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// The tool names a plugin's server goes by, and the names an earlier release went by, read wherever the bare `mcp__<server>__` form is.
struct PluginToolNameTests {
    private static let gizmo = ProductName(word: "gizmo", displayName: "Gizmo")

    private static var word: String {
        ProductName.current.word
    }

    @Test func aPluginFormNameNamesItsTool() {
        #expect(IndexToolName.tool(named: "mcp__plugin_\(Self.word)_\(Self.word)__digest") == "digest")
        #expect(IndexToolName.tool(named: "mcp__plugin_acme-tools_\(Self.word)__where") == "where")
    }

    @Test func theLastServerSeparatorDecidesWhereThePluginNameEnds() {
        #expect(IndexToolName.tool(named: "mcp__plugin_\(Self.word)_x_\(Self.word)__search") == "search")
        #expect(IndexToolName.tool(named: "mcp__plugin_\(Self.word)__\(Self.word)__search") == "search")
    }

    @Test func nearMissesAreNotTheServer() {
        #expect(IndexToolName.tool(named: "mcp__plugin_x_\(Self.word)x__digest") == nil)
        #expect(IndexToolName.tool(named: "mcp__\(Self.word)ly__digest") == nil)
        #expect(IndexToolName.tool(named: "mcp__plugin__\(Self.word)__digest") == nil)
        #expect(IndexToolName.tool(named: "mcp__plugin_x_x\(Self.word)__digest") == nil)
        #expect(IndexToolName.tool(named: "plugin_x_\(Self.word)__digest") == nil)
    }

    @Test func aLegacyNameIsRecognisedBesideTheCurrentOne() {
        let products = [Self.gizmo, ProductName.current]

        #expect(IndexToolName.tool(named: "mcp__gizmo__digest", recognising: products) == "digest")
        #expect(IndexToolName.tool(named: "mcp__\(Self.word)__digest", recognising: products) == "digest")
        #expect(IndexToolName.tool(named: "mcp__plugin_gizmo_gizmo__where", recognising: products) == "where")
        #expect(IndexToolName.tool(named: "mcp__gizmo__digest", recognising: [ProductName.current]) == nil)
    }

    @Test func aServerNameIsRecognisedBareOrAsAPluginShipsIt() {
        #expect(IndexToolName.isServer(Self.word))
        #expect(IndexToolName.isServer("plugin:\(Self.word):\(Self.word)"))
        #expect(IndexToolName.isServer("plugin_\(Self.word)_\(Self.word)"))
        #expect(!IndexToolName.isServer("\(Self.word)x"))
        #expect(!IndexToolName.isServer("plugin:\(Self.word):other"))
        #expect(IndexToolName.isServer("gizmo", recognising: [Self.gizmo]))
        #expect(!IndexToolName.isServer("gizmo", recognising: [ProductName.current]))
    }

    @Test func theAdviceHookReadsAPluginFormCallAsTheAdviceTaken() {
        #expect(PreToolUseCommand.takesTheAdvice(command: nil, payload: ["tool_name": "mcp__plugin_\(Self.word)_\(Self.word)__digest"]))
        #expect(!PreToolUseCommand.takesTheAdvice(command: nil, payload: ["tool_name": "mcp__plugin_x_\(Self.word)x__digest"]))
    }

    @Test func anAllowlistTokenForAPluginsServerAdmitsAllOfIt() {
        let path = URL(fileURLWithPath: "/tmp/worker.md")
        let list = AgentAllowlist(name: "worker", path: path, tools: ["Read", "mcp__plugin_\(Self.word)_\(Self.word)__*"])
        let near = AgentAllowlist(name: "worker", path: path, tools: ["Read", "mcp__plugin_x_\(Self.word)x__*"])

        #expect(list.missing.isEmpty)
        #expect(near.shutsTheIndexOut)
    }

    @Test func theHookMatchersCoverThePluginFormBesideTheBareOne() {
        let matchers = SiftClaudeSetup.hooks.events.flatMap(\.matchers)

        #expect(matchers.contains { $0.contains("|mcp__plugin_.*_\(Self.word)__.*|") })
        #expect(matchers.contains { $0.contains("|mcp__plugin_.*_\(Self.word)__digest|") })
    }

    @Test func everyRecognisedBinaryNameIsABinary() {
        #expect(ProductName.isBinary(ProductName.current.binary))
        #expect(!ProductName.isBinary(ProductName.current.binary + "x"))
    }
}
