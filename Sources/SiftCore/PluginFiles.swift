//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The text of each file of the Claude Code plugin, generated from the code that registers the same hooks, server and rule for `swift-sure install`.
///
/// The files are keyed by their path under the plugin root. JSON is written with sorted keys and two-space indentation and every file ends in a newline, so the output is stable and a committed copy can be compared byte for byte.
public struct PluginFiles {
    /// The path of the manifest under the plugin root.
    public static var manifestFilePath: String {
        ".claude-plugin/plugin.json"
    }

    /// The path of the hooks file under the plugin root.
    public static var hooksFilePath: String {
        "hooks/hooks.json"
    }

    /// The path of the MCP server file under the plugin root.
    public static var serverFilePath: String {
        ".mcp.json"
    }

    /// The path of the skill under the plugin root.
    public static func skillPath(for product: ProductName = .current) -> String {
        "skills/\(product.word)/SKILL.md"
    }

    /// Every file of the plugin, by path under its root.
    ///
    /// `rule` is the agent rule as `SwiftSure.md` holds it; its front matter is dropped, because a skill carries its own.
    public static func render(
        rule: String,
        product: ProductName = .current,
        events: [HookRegistration.Event] = SiftClaudeSetup.events,
        server: ClaudeMcpServer = SiftClaudeSetup.server
    ) throws -> [String: String] {
        try [
            manifestFilePath: json(manifest(product: product)),
            hooksFilePath: json(["hooks": hooks(events: events, product: product)]),
            serverFilePath: json(["mcpServers": [server.name: ["command": product.binary, "args": server.arguments]]]),
            skillPath(for: product): skill(rule: rule, product: product),
        ]
    }

    /// The rule's text without its front matter.
    public static func ruleBody(of rule: String) -> String {
        guard rule.hasPrefix("---\n"), let close = rule.range(of: "\n---\n", range: rule.index(rule.startIndex, offsetBy: 3) ..< rule.endIndex) else {
            return rule
        }
        return String(rule[close.upperBound...].drop { $0 == "\n" })
    }

    /// A hook matcher in the plugin's tool-name form: the installer's own spelling of the server's tools and the pattern that also matched a plugin's, replaced by the one name the harness gives a plugin's tool.
    static func pluginMatcher(_ matcher: String, product: ProductName) -> String {
        let specific = ProductName.pluginToolPrefix + product.word + "_" + product.pluginServerSegment + "__"
        var translated = matcher
        for suffix in [".*", "digest"] {
            translated = translated.replacingOccurrences(of: "|" + product.pluginToolMatcher(suffix), with: "")
        }
        return translated.replacingOccurrences(of: product.toolPrefix, with: specific)
    }

    private static func manifest(product: ProductName) -> [String: Any] {
        [
            "name": product.word,
            "description": "\(product.displayName) answers questions about Swift code from an index, and runs builds and tests with their output cut to the answer.",
            "version": SiftVersion.current,
        ]
    }

    private static func hooks(events: [HookRegistration.Event], product: ProductName) -> [String: Any] {
        var byEvent: [String: Any] = [:]
        for event in events {
            let hook: [String: Any] = ["type": "command", "command": "\(product.binary) \(event.subcommand)", "timeout": event.timeout]
            let entries: [[String: Any]] = event.matchers.isEmpty
                ? [["hooks": [hook]]]
                : event.matchers.map { ["matcher": pluginMatcher($0, product: product), "hooks": [hook]] }
            byEvent[event.name] = (byEvent[event.name] as? [[String: Any]] ?? []) + entries
        }
        return byEvent
    }

    private static func skill(rule: String, product: ProductName) -> String {
        let description = "Use when reading, searching, building or testing Swift code: answer from the \(product.displayName) index instead of grepping or reading files by hand, and run every build and test as \(product.binary) run -- <command> from Bash, in the foreground, never piped."
        return "---\nname: \(product.word)\ndescription: \(description)\n---\n\n" + ruleBody(of: rule)
    }

    private static func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text + "\n"
    }
}
