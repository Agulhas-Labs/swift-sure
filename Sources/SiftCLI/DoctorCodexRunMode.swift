//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Codex checks for a run-mode install: hooks and no MCP server.
///
/// swift-fieldwork's `DoctorCodex` fails when no server is registered, which for a run-mode install would be a fault that is not one. So this reads the hooks with the run-mode registration, drops the server checks, says the index is off as information, and runs the binary check on the command the hooks file registers.
struct DoctorCodexRunMode {
    let home: AgentPaths.CodexHome
    let runner: any CodexMcpRunner
    let probe: DoctorProbe
    let expectedTools: [String]

    /// Whether the Codex home's hooks file registers the run-mode set, which is what makes an install a run-mode one.
    static func applies(home: AgentPaths.CodexHome) -> Bool {
        let file = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        return SiftCodexSetup.mode(of: try? Data(contentsOf: file)) == .run
    }

    /// The checks for the hooks and their trust, the informational index line, the binary, then each hook's run, in the order the index-mode answer lists them.
    func checks() -> [DoctorCheck] {
        let doctor = DoctorCodex(home: home, runner: runner, probe: probe, hooks: SiftCodexSetup.runHooks, server: SiftCodexSetup.server, expectedTools: expectedTools)
        let all = doctor.checks().filter { $0.name != "server" && $0.name != "mcp server" }
        let setup = all.prefix { $0.name == "hooks" || $0.name == "trust" }
        var checks = Array(setup)
        let file = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let hooksData = try? Data(contentsOf: file)
        checks.append(SiftCodexSetup.registersBothModes(hooksData) ? .fail(.codex, "index", "both modes registered; re-run \(ProductName.current.binary) install (with or without --run-only)") : .pass(.codex, "index", "off (installed with --run-only)"))
        if let command = Self.firstCommand(in: hooksData) {
            checks += DoctorRun(agent: .codex, probe: probe, expectedTools: expectedTools).binaryChecks(DoctorClaudeRunMode.binary(of: command))
        }
        return checks + all.dropFirst(setup.count)
    }

    /// The first command of this tool's registered for the run-mode `PreToolUse` hook.
    static func firstCommand(in data: Data?) -> String? {
        SiftCodexSetup.runHooksFile.hooks.first.flatMap { SiftCodexSetup.runHooksFile.commands(in: data, for: $0).first }
    }
}
