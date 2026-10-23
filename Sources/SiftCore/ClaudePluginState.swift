//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Whether this tool's Claude Code plugin is enabled on the machine an environment describes, and what `install` left behind that the plugin now owns.
///
/// The plugin counts as enabled when its id, the product word and a marketplace, has a user-scope record in `plugins/installed_plugins.json` under Claude Code's configuration directory and the user settings do not set it to `false`. A project-scope record is not counted: it does not switch the user-scope registration off in every other project. A missing or unreadable file means not enabled.
public struct ClaudePluginState {
    private let environment: [String: String]

    public init(environment: [String: String]) {
        self.environment = environment
    }

    /// The enabled plugin's id, `<product word>@<marketplace>`, or `nil` when it is not enabled; the first by sorted id where several marketplaces qualify.
    public var enabledID: String? {
        let prefix = ProductName.current.word + "@"
        let records = Self.userScopeIDs(in: AgentPaths.claudeDirectory(environment: environment).appendingPathComponent("plugins/installed_plugins.json"))
        let flags = Self.object(at: AgentPaths.claudeSettings(environment: environment))?["enabledPlugins"] as? [String: Any]
        return records
            .filter { $0.hasPrefix(prefix) && $0.count > prefix.count && (flags?[$0] as? Bool) != false }
            .min()
    }

    /// What `install` wrote that is still there, in the order hooks, MCP entry, rule: the names the skip line gives.
    public var installerLeftovers: [String] {
        var found: [String] = []
        let settings = try? Data(contentsOf: AgentPaths.claudeSettings(environment: environment))
        if SiftClaudeSetup.hooks(recognising: ProductName.recognised).contains(where: { !$0.fingerprint(of: settings).isEmpty }) {
            found.append("hooks")
        }
        let config = AgentPaths.claudeConfig(environment: environment)
        if ProductName.recognised.contains(where: { UninstallServers.userServer(in: config, named: $0)?.ours == true }) {
            found.append("MCP entry")
        }
        if FieldworkTool.recognised.contains(where: { FileManager.default.fileExists(atPath: AgentPaths.claudeRule(named: $0.installedRuleName, environment: environment).path) }) {
            found.append("rule")
        }
        return found
    }

    /// The Claude Code step's one line when the plugin is enabled: that the plugin owns the registration, and, where `install` left some of it, which parts and the way out.
    public var installSkipLine: String {
        let binary = ProductName.current.binary
        var line = "claude: the \(binary) plugin is enabled, so hooks, the MCP server and the rule come from it and are left alone"
        let leftovers = installerLeftovers
        if !leftovers.isEmpty {
            let named = leftovers.count > 1 ? leftovers.dropLast().joined(separator: ", ") + " and " + leftovers[leftovers.count - 1] : leftovers[0]
            line += "; \(named) still present from \(binary) install: run \(binary) uninstall, then \(binary) install"
        }
        return line
    }

    /// The install summary's entry for Claude Code when the plugin is enabled: the step wrote nothing because the plugin owns the registration.
    public static var installSummaryVerdict: String {
        "\(Agent.claude.harness): left to the \(ProductName.current.binary) plugin"
    }

    /// The line `uninstall` adds for the enabled plugin `id`: that it stays, and the command that removes it.
    public static func uninstallLine(for id: String) -> String {
        "plugin: \(id) is enabled and left in place; claude plugin uninstall \(id) removes it"
    }

    private static func userScopeIDs(in file: URL) -> [String] {
        guard let plugins = object(at: file)?["plugins"] as? [String: Any] else { return [] }
        return plugins.compactMap { id, records in
            let isUser = (records as? [[String: Any]])?.contains { ($0["scope"] as? String) == "user" } ?? false
            return isUser ? id : nil
        }
    }

    private static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
