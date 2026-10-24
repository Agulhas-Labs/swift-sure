//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The Claude Code checks for a run-mode install, the default: hooks and no MCP server.
///
/// swift-fieldwork's `DoctorClaude` fails when no server is registered and runs nothing after that, which for a run-mode install would be a fault that is not one. So this reads the hooks with the run-mode registration, says the index is off as information, and runs the binary and hook checks on the commands the settings file registers.
struct DoctorClaudeRunMode {
    let environment: [String: String]
    let probe: DoctorProbe
    let expectedTools: [String]

    /// Whether the settings file registers the run-mode set, which is what makes an install a run-mode one.
    static func applies(environment: [String: String]) -> Bool {
        let settings = AgentPaths.claudeSettings(environment: environment)
        return SiftClaudeSetup.mode(of: try? Data(contentsOf: settings)) == .run
    }

    /// Every check, in the order the index-mode answer lists them: hooks, the informational index line, the binary, then each hook.
    func checks() -> [DoctorCheck] {
        let doctor = DoctorClaude(environment: environment, probe: probe, hooks: SiftClaudeSetup.runHooks, server: SiftClaudeSetup.server, expectedTools: expectedTools)
        var checks = doctor.checks().filter { $0.name == "hooks" }
        checks.append(.pass(.claude, "index", "off (installed with --run-only)"))
        let registered = Self.registeredCommands(in: try? Data(contentsOf: AgentPaths.claudeSettings(environment: environment)))
        guard let first = registered.first else { return checks }
        let run = DoctorRun(agent: .claude, probe: probe, expectedTools: expectedTools)
        checks += run.binaryChecks(Self.binary(of: first.command))
        for hook in registered {
            checks.append(run.hook(hook.event, command: hook.command, payload: doctor.payload(for: hook.event), jsonOnly: true))
        }
        return checks
    }

    /// The first command of this tool's registered for each run-mode event.
    static func registeredCommands(in data: Data?) -> [(event: String, command: String)] {
        let settings = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let registered = settings?["hooks"] as? [String: Any] ?? [:]
        return SiftClaudeSetup.runEvents.compactMap { event in
            let entries = registered[event.name] as? [[String: Any]] ?? []
            let commands = entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
            return commands.first { SiftClaudeSetup.runHooks.isOurs($0, subcommand: event.subcommand) }.map { (event.name, $0) }
        }
    }

    /// The first shell word of `command`: the binary, as `ShellWord.quoted` wrote it.
    static func binary(of command: String) -> String {
        var word = ""
        var quoted = false
        for character in command {
            if character == "'" {
                quoted.toggle()
            } else if character == " ", !quoted {
                break
            } else {
                word.append(character)
            }
        }
        return word
    }
}
