//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// What SwiftSure registers with Claude Code, pinned as literals: the hook events and matchers, the MCP server registration and removal, and the rule, as the install wrote them before the library took over the mechanics.
struct SiftClaudeSetupTests {
    @Test
    func theHooksRegisteredAreExactlyTheseEventsMatchersAndTimeouts() {
        let events = SiftClaudeSetup.hooks.events.map { Registered(name: $0.name, subcommand: $0.subcommand, matchers: $0.matchers, timeout: $0.timeout) }

        #expect(events == [
            Registered(name: "SessionStart", subcommand: "session-start", matchers: ["startup", "resume", "clear", "compact"], timeout: 5),
            Registered(name: "SubagentStart", subcommand: "session-start", matchers: [], timeout: 5),
            Registered(
                name: "PreToolUse",
                subcommand: "pre-tool-use",
                matchers: ["Bash|Read|Grep|Glob|mcp__xcode__Xcode(Read|Grep|Glob)|mcp__swift-sure__.*|mcp__plugin_.*_swift-sure__.*|Write|Edit|MultiEdit"],
                timeout: 5
            ),
            Registered(name: "PostToolUse", subcommand: "post-tool-use", matchers: ["Write|Edit|MultiEdit|mcp__swift-sure__digest|mcp__plugin_.*_swift-sure__digest|Grep|Bash"], timeout: 3),
            Registered(name: "PostToolUseFailure", subcommand: "post-tool-use", matchers: ["Bash"], timeout: 3),
            Registered(name: "Stop", subcommand: "stop", matchers: [], timeout: 5),
            Registered(name: "SubagentStop", subcommand: "stop", matchers: [], timeout: 5),
        ])
        #expect(SiftClaudeSetup.sessionStartMatchers == ["startup", "resume", "clear", "compact"])
    }

    @Test
    func theToolIdentityNamesSiftAndTheSubcommandsItsHooksRun() {
        #expect(FieldworkTool.sift.name == "swift-sure")
        #expect(FieldworkTool.sift.hookSubcommands == ["session-start", "session-start", "pre-tool-use", "post-tool-use", "post-tool-use", "stop", "stop"])
        #expect(FieldworkTool.sift.installedRuleName == "swift-sure.md")
        #expect(SiftClaudeSetup.hooks.tool == FieldworkTool.sift)
    }

    @Test
    func theServerIsRegisteredAtUserScopeUnderTheNameSiftRunningMcp() {
        let server = SiftClaudeSetup.server

        #expect(server.addArguments(binary: "/opt/tools/bin/swift-sure") == ["mcp", "add", "--transport", "stdio", "--scope", "user", "swift-sure", "--", "/opt/tools/bin/swift-sure", "mcp"])
        #expect(server.manual(binary: "/opt/my tools/swift-sure") == "claude mcp add --transport stdio --scope user swift-sure -- '/opt/my tools/swift-sure' mcp")
        #expect(server.registered(binary: "/opt/tools/bin/swift-sure") == "/opt/tools/bin/swift-sure mcp")
        #expect(server.removalArguments == [["mcp", "remove", "swift-sure", "--scope", "user"]])
        #expect(server.removalCommand == "claude mcp remove swift-sure --scope user")
        #expect(SiftClaudeSetup.mcp.server == server)
    }

    @Test(arguments: [
        ["-y", "@agulhas-labs/sift", "mcp"],
        ["--yes", "@agulhas-labs/sift", "mcp"],
        ["-y", "@agulhas-labs/sift@0.1.3", "mcp"],
    ])
    func anNpxRegisteredServerIsSiftsAndIsPlannedAsStale(arguments: [String]) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sift-claude-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent(".claude.json")
        let entry: [String: Any] = ["type": "stdio", "command": "npx", "args": arguments, "env": [String: String]()]
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["swift-sure": entry]]).write(to: config)

        let plan = SiftClaudeSetup.mcp.plan(config: config, binary: "/opt/tools/bin/swift-sure")

        #expect(plan == .stale("npx " + arguments.joined(separator: " ")))
    }

    @Test
    func theRuleShipsAsSiftMdAndLoadsOnSwiftFiles() {
        let rule = SiftClaudeSetup.rule

        #expect(rule.shippedFileName == "SwiftSure.md")
        #expect(rule.shareDirectory == "swift-sure")
        #expect(rule.loadsOn == "**/*.swift")
        #expect(rule.noSourceReason(exists: false) == "no SwiftSure.md ships with this binary (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)")
        #expect(rule.noSourceReason(exists: true) == "no SwiftSure.md ships beside this binary to refresh it from (install.sh writes it; `swift-sure install` from Homebrew or npm copies the SwiftSure.md they ship)")
    }

    /// The benchmark marks an arm-B run invalid for any hook event outside its list, so a registered event missing from it throws out every run that fires it.
    @Test
    func theBenchmarkAllowsEveryEventSiftRegisters() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent() // SiftCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent()
        let bench = try String(contentsOf: root.appendingPathComponent("Benchmarks/bench.py"), encoding: .utf8)
        let line = try #require(bench.split(separator: "\n").first { $0.hasPrefix("SIFT_HOOK_EVENTS = {") })
        let listed = line.drop { $0 != "{" }.dropFirst().prefix { $0 != "}" }
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }

        #expect(Set(listed) == Set(SiftClaudeSetup.events.map(\.name)))
    }
}

extension SiftClaudeSetupTests {
    private struct Registered: Equatable {
        let name: String
        let subcommand: String
        let matchers: [String]
        let timeout: Int
    }
}
