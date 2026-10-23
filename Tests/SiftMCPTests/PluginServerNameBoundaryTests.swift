//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Where a server name ends and a plugin's begins, in a tool name and in an allowlist.
struct PluginServerNameBoundaryTests {
    private static var word: String {
        ProductName.current.word
    }

    private static func definition(_ tools: [String]) -> AgentAllowlist {
        AgentAllowlist(name: "reviewer", path: URL(fileURLWithPath: "/tmp/reviewer.md"), tools: tools)
    }

    private static var bareTools: [String] {
        MCPToolCatalog.tools(loadUpFront: false).compactMap { $0["name"] as? String }
    }

    @Test func aPartialWildcardIsAPrefixOfToolNamesNotTheWholeServer() {
        let definition = Self.definition(["mcp__\(Self.word)__dig*"])

        #expect(definition.missing == IndexToolName.qualified.filter { !$0.hasSuffix("__digest") })
        #expect(!definition.missing.isEmpty)
    }

    @Test func aPartialWildcardInThePluginSpellingIsAPrefixToo() {
        let definition = Self.definition(["mcp__plugin_\(Self.word)_\(Self.word)__dig*"])

        #expect(definition.missing.count == Self.bareTools.count - 1)
        #expect(!definition.missing.contains { $0.hasSuffix("__digest") })
    }

    @Test func theBareServerWildcardAdmitsEveryTool() {
        #expect(Self.definition(["mcp__\(Self.word)__*"]).missing.isEmpty)
        #expect(Self.definition(["mcp__plugin_\(Self.word)_\(Self.word)__*"]).missing.isEmpty)
    }

    @Test func theBarePluginServerTokenAdmitsEveryTool() {
        let definition = Self.definition(["mcp__plugin_\(Self.word)_\(Self.word)"])

        #expect(definition.missing.isEmpty)
        #expect(!definition.shutsTheIndexOut)
    }

    @Test func anExactListInThePluginSpellingAdmitsTheToolsItNames() {
        let definition = Self.definition(Self.bareTools.map { "mcp__plugin_\(Self.word)_\(Self.word)__\($0)" })

        #expect(definition.missing.isEmpty)
        #expect(!definition.shutsTheIndexOut)
        #expect(Self.definition(["mcp__plugin_acme_\(Self.word)__where"]).missing == IndexToolName.qualified.filter { !$0.hasSuffix("__where") })
    }

    @Test func aColonFormServerIsOursOnlyByItsWholeName() {
        #expect(IndexToolName.isServer("plugin:acme:\(Self.word)"))
        #expect(!IndexToolName.isServer("plugin:acme:my_\(Self.word)"))
        #expect(IndexToolName.isServer("plugin_acme_\(Self.word)"))
    }
}
