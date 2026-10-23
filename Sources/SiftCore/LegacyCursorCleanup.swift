//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The install's and the uninstall's cleanup of what an earlier release registered in Cursor under its own name: its `mcp.json` server and its `hooks.json` hooks.
public struct LegacyCursorCleanup {
    /// The flag a refusal of either file names.
    private static let flag = SiftCursorSetup.install.directoryFlag

    /// Takes out, for each earlier name, the server and the hooks `directory` holds that run this tool, returning the lines to print and the files written.
    ///
    /// Ownership is what the uninstall counts: the earlier name's binary run with `mcp` for the server, and its binary with each hook's subcommand and the `--agent cursor` flag for the hooks. A server named for an earlier release that runs something else is left and unmentioned, since an install that runs on every upgrade should not keep naming it. With `installing`, a legacy server stays until the current name's server is in `mcp.json` and legacy hooks stay when `installFailed`, each with a line naming the install that settles it, so the cleanup never leaves a machine with neither. The uninstall passes `installing: false` and takes out what is ours under every name.
    ///
    /// Each file is backed up once a run, under the current name and from the bytes it had before the run's first rewrite: `written` is what the step before this one already rewrote, and a file named there, or by an earlier pass here, is rewritten with no backup of its own.
    public static func settle(directory: URL, installing: Bool, installFailed: Bool = false, written: [String] = []) throws -> InstallOutcome {
        var outcome = InstallOutcome()
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        var mcpData = try SettingsFile.read(mcpURL, agent: "cursor", flag: flag)
        var hooksData = try SettingsFile.read(hooksURL, agent: "cursor", flag: flag)
        let current = ProductName.current
        var rewritten = Set(written)
        let serverInPlace = try !installing || SettingsFile.merge(mcpURL, agent: "cursor") { try SiftCursorSetup.mcp.remove(from: mcpData) }.changed
        let currentHeldByAnother = !serverInPlace && holdsServer(mcpData, named: current.mcpServer)
        for (name, legacy) in zip(ProductName.recognised, SiftCursorSetup.recognisedInstalls).dropFirst() {
            let server = try SettingsFile.merge(mcpURL, agent: "cursor") { try legacy.mcp.remove(from: mcpData) }
            if case let .removed(existing) = server.outcome {
                if serverInPlace {
                    outcome.lines.append("mcp: removed the server \(name.mcpServer) an earlier release registered — \(existing)")
                    try SettingsFile.write(&outcome, mcpURL, server.data, original: rewritten.contains(SettingsFile.named(mcpURL)) ? nil : mcpData, if: true, tool: .sift)
                    rewritten.insert(SettingsFile.named(mcpURL))
                    mcpData = server.data
                } else if currentHeldByAnother {
                    outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was left — a server named \(current.mcpServer) runs something else")
                } else {
                    outcome.lines.append("mcp: the server \(name.mcpServer) an earlier release registered was left, since \(current.mcpServer) is not registered; run: \(current.binary) install")
                }
            }
            let hooks = try SettingsFile.merge(hooksURL, agent: "cursor") { try legacy.hooks.remove(from: hooksData) }
            guard hooks.changed else { continue }
            if installFailed {
                outcome.lines.append("hooks: the earlier release's hooks (\(name.binary)) were left, since \(current.binary)'s were not all registered; run: \(current.binary) install")
            } else {
                outcome.lines.append("hooks: removed the earlier release's hooks (\(name.binary))")
                try SettingsFile.write(&outcome, hooksURL, hooks.data, original: rewritten.contains(SettingsFile.named(hooksURL)) ? nil : hooksData, if: true, tool: .sift)
                rewritten.insert(SettingsFile.named(hooksURL))
                hooksData = hooks.data
            }
        }
        return outcome
    }

    /// Whether the `mcp.json` bytes name a server `name`.
    private static func holdsServer(_ data: Data?, named name: String) -> Bool {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["mcpServers"] as? [String: Any])?[name] != nil
    }
}
