//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Codex step of `swift-sure install`: the hooks in the Codex home and the server through `codex mcp`, through the same installer as `install-hook --agent codex`, without its exit.
struct CodexInstallStep {
    /// Installs `binary` into the Codex home `directory` names, else the one `environment` names, printing to `output`.
    static func run(binary: String, environment: [String: String], directory: String? = nil, runner: any CodexMcpRunner, output: CommandOutput) throws -> InstallStepReport {
        let home = CodexInstall.home(flag: directory, environment: environment)
        let outcome = try CodexHookInstaller.installing(home: home, binary: binary, runner: runner, output: output)
        // `codex mcp add` writes config.toml itself, so a registration is a change the written files do not show.
        let registered = outcome.lines.contains { $0.hasPrefix("mcp: registered") || $0.hasPrefix("mcp: replaced") || $0.hasPrefix("mcp: removed") }
        return InstallStepReport(agent: .codex, written: outcome.written, registered: registered, failures: outcome.failures)
    }
}
