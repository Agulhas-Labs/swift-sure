//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Cursor checks for a run-mode install: hooks and no MCP server.
///
/// swift-fieldwork's `DoctorCursor` fails when no server is registered and runs nothing after that, which for a run-mode install would be a fault that is not one. So this reads the hooks with the run-mode registration, says the index is off as information, and runs the binary and hook checks on the commands `hooks.json` registers.
struct DoctorCursorRunMode {
    let directory: URL
    let probe: DoctorProbe
    let expectedTools: [String]

    /// Whether `hooks.json` in `directory` registers the run set, which is what makes an install a run-mode one.
    static func applies(directory: URL) -> Bool {
        SiftCursorSetup.mode(of: try? Data(contentsOf: directory.appendingPathComponent(CursorHooksFile.fileName))) == .run
    }

    /// Every check, in the order the index-mode answer lists them: hooks, the informational index line, the binary, then each hook.
    func checks() -> [DoctorCheck] {
        let doctor = DoctorCursor(directory: directory, probe: probe, install: CursorInstall(mcp: SiftCursorSetup.mcp, hooks: SiftCursorSetup.runHooks, directoryFlag: SiftCursorSetup.install.directoryFlag), expectedTools: expectedTools)
        var checks = doctor.checks().filter { $0.name == "hooks" }
        let hooksData = try? Data(contentsOf: directory.appendingPathComponent(CursorHooksFile.fileName))
        checks.append(SiftCursorSetup.registersBothModes(hooksData) ? .fail(.cursor, "index", "both modes registered; re-run \(ProductName.current.binary) install (with or without --run-only)") : .pass(.cursor, "index", "off (installed with --run-only)"))
        let registered = Self.registeredCommands(in: hooksData)
        guard let first = registered.first else { return checks }
        let run = DoctorRun(agent: .cursor, probe: probe, expectedTools: expectedTools)
        checks += run.binaryChecks(DoctorClaudeRunMode.binary(of: first.command))
        for hook in registered {
            checks.append(run.hook(hook.event, command: hook.command, payload: doctor.payload(for: hook.event), jsonOnly: true))
        }
        return checks
    }

    /// The first command of this tool's registered for each run-mode event.
    static func registeredCommands(in data: Data?) -> [(event: String, command: String)] {
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let events = file?["hooks"] as? [String: Any] ?? [:]
        let set = SiftCursorSetup.runHooks
        return set.hooks.compactMap { hook in
            let commands = (events[hook.event] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            return commands.first { set.tool.runs($0, subcommand: set.registeredSubcommand(for: hook)) }.map { (hook.event, $0) }
        }
    }
}
