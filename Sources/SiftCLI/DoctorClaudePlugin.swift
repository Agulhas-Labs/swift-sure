//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Claude Code checks `doctor` runs, in place of the installer's, when this tool's plugin is enabled.
struct DoctorClaudePlugin {
    let id: String
    let leftovers: [String]
    let pathLookup: (String) -> URL?

    /// The plugin for an environment, or `nil` when it is not enabled.
    init?(environment: [String: String], pathLookup: @escaping (String) -> URL?) {
        let state = ClaudePluginState(environment: environment)
        guard let id = state.enabledID else { return nil }
        self.id = id
        leftovers = state.installerLeftovers
        self.pathLookup = pathLookup
    }

    /// The plugin line (a pass where the plugin owns the registration, a fail where it is also registered by `install`), then the PATH line.
    var checks: [DoctorCheck] {
        let binary = ProductName.current.binary
        var found: [DoctorCheck] = []
        if leftovers.isEmpty {
            found.append(.pass(.claude, "plugin", "\(id) is enabled; hooks, the MCP server and the rule come from it"))
        } else {
            found.append(.fail(.claude, "plugin", "registered twice, by the \(binary) plugin and by \(binary) install; run \(binary) uninstall then \(binary) install to keep the plugin, or claude plugin uninstall \(id) to keep the install"))
        }
        if let resolved = pathLookup(binary) {
            found.append(.pass(.claude, "path", resolved.path))
        } else {
            found.append(.fail(.claude, "path", "the \(binary) plugin runs \(binary) from PATH, and \(binary) is not on it; link it into a directory that is"))
        }
        return found
    }
}
