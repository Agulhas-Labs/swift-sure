//
// Copyright © Agulhas Labs
//

import Foundation

/// The install's cleanup of what an earlier release registered under its own name: its user-scope MCP server and its agent rule, each taken out only once the current name's is in place.
public struct LegacyRegistrationCleanup {
    /// Takes out, for each of `names` after the first, the user-scope server `locations` shows under that name when it runs this tool, and the agent rule beside the current one, returning the lines to print and whether anything came out.
    ///
    /// A server counts as this tool's by what `uninstall` counts: the name's binary run with `mcp` alone, or the package under `npx`; one named the same that runs something else is left alone and unmentioned, since an install that runs on every upgrade should not keep naming it. A rule that is a symlink is left, as ``SiftUninstall`` leaves one. A legacy server stays until the current name's server is registered and a legacy rule until the current rule exists, with a note naming the install that registers them, so the cleanup never leaves a machine with neither. A missing or failing `claude` is a note naming the command to run, never a failure of the install.
    public static func settle(
        _ locations: SiftUninstall.Locations,
        names: [ProductName],
        removeServer: (ProductName, SiftUninstall.ServerScope) -> SiftUninstall.ServerRemoval
    ) -> (lines: [String], removed: Bool) {
        var lines: [String] = []
        var removed = false
        let rules = locations.rule.deletingLastPathComponent()
        let current = names.first ?? ProductName.current
        let currentRule = rules.appendingPathComponent("\(current.binary).md")
        let currentServerRegistered = UninstallServers.userServer(in: locations.claudeConfig, named: current)?.ours == true
        let currentRuleInstalled = FileManager.default.fileExists(atPath: currentRule.path)
        for legacy in names.dropFirst() {
            if let entry = UninstallServers.userServer(in: locations.claudeConfig, named: legacy), entry.ours, !currentServerRegistered {
                lines.append("mcp: the user-scope server \(legacy.mcpServer) an earlier release registered was left, since \(current.mcpServer) is not registered; run: \(current.binary) install")
            } else if let entry = UninstallServers.userServer(in: locations.claudeConfig, named: legacy), entry.ours {
                let command = SiftClaudeSetup.server(named: legacy).removalCommand
                switch removeServer(legacy, .user) {
                case .removed:
                    lines.append("mcp: removed the user-scope server \(legacy.mcpServer) an earlier release registered — \(entry.command)")
                    removed = true
                case let .failed(reason):
                    lines.append("mcp: the user-scope server \(legacy.mcpServer) an earlier release registered was not removed (\(reason)); run: \(command)")
                case .noClaude:
                    lines.append("mcp: the user-scope server \(legacy.mcpServer) an earlier release registered was not removed — `claude` is not on PATH; run: \(command)")
                }
            }
            let rule = rules.appendingPathComponent("\(legacy.binary).md")
            guard rule != currentRule else { continue }
            guard currentRuleInstalled || (try? FileManager.default.attributesOfItem(atPath: rule.path)) == nil else {
                lines.append("rule: \(rule.path) an earlier release installed was left, since \(currentRule.lastPathComponent) is not installed; run: \(current.binary) install")
                continue
            }
            do {
                switch try SiftUninstall.removeRule(at: rule) {
                case let .removed(line):
                    lines.append(line)
                    removed = true
                case let .left(note):
                    lines.append(note)
                case nil:
                    break
                }
            } catch {
                lines.append("rule: not removed — \(rule.path): \(error.localizedDescription)")
            }
        }
        return (lines, removed)
    }

    /// What ``settle(_:names:removeServer:)`` would print for `locations` once the install has run, as `--dry-run` says it, given whether the current name's server and rule would then be in place.
    public static func pending(_ locations: SiftUninstall.Locations, names: [ProductName], serverRegistered: Bool, ruleInstalled: Bool, claudeOnPath: Bool) -> [String] {
        var lines: [String] = []
        let rules = locations.rule.deletingLastPathComponent()
        let current = names.first ?? ProductName.current
        let currentRule = rules.appendingPathComponent("\(current.binary).md")
        for legacy in names.dropFirst() {
            if let entry = UninstallServers.userServer(in: locations.claudeConfig, named: legacy), entry.ours {
                if !serverRegistered {
                    lines.append("mcp: the user-scope server \(legacy.mcpServer) an earlier release registered would be left, since \(current.mcpServer) would not be registered")
                } else if claudeOnPath {
                    lines.append("mcp: would remove the user-scope server \(legacy.mcpServer) an earlier release registered — \(entry.command)")
                } else {
                    lines.append("mcp: the user-scope server \(legacy.mcpServer) an earlier release registered would not be removed — `claude` is not on PATH; run: \(SiftClaudeSetup.server(named: legacy).removalCommand)")
                }
            }
            let rule = rules.appendingPathComponent("\(legacy.binary).md")
            guard rule != currentRule, let type = try? FileManager.default.attributesOfItem(atPath: rule.path)[.type] as? FileAttributeType else { continue }
            if !ruleInstalled {
                lines.append("rule: \(rule.path) an earlier release installed would be left, since \(currentRule.lastPathComponent) would not be installed")
            } else if type == .typeSymbolicLink {
                lines.append("rule: \(rule.path) is a symlink — would be left as is")
            } else {
                lines.append("rule: would remove \(rule.path), which an earlier release installed")
            }
        }
        return lines
    }
}
