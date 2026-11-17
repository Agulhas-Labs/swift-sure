//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SiftCore

/// The Codex half of `install-hook` and `uninstall-hook`: runs ``SiftCodexSetup`` and says what it did, starting with the Codex home it used.
struct SiftCodexHookInstaller {
    /// Registers the hooks and the server in `home` for `binary`, an absolute path, and prints the answer; exits 1 when the server could not be registered.
    @discardableResult
    static func install(home: AgentPaths.CodexHome, binary: String, runner: any CodexMcpRunner, output: CommandOutput, mode: SiftClaudeSetup.InstallMode = .index) throws -> InstallOutcome {
        let outcome = try installing(home: home, binary: binary, runner: runner, output: output, mode: mode)
        try exit(outcome)
        return outcome
    }

    /// The install without the exit: prints the answer and returns what it did, a server that could not be registered among its failures.
    static func installing(home: AgentPaths.CodexHome, binary: String, runner: any CodexMcpRunner, output: CommandOutput, mode: SiftClaudeSetup.InstallMode = .index) throws -> InstallOutcome {
        output.emit(home.line)
        let result = try SiftCodexSetup.installing(home: home, binary: binary, runner: runner, mode: mode)
        // The home line already went out, before the install ran, so a refusal names the home.
        for line in result.printed.dropFirst() {
            output.emit(line)
        }
        return result.outcome
    }

    /// Takes out what the install wrote in `home` and prints the answer; exits 1 when the server could not be removed.
    static func uninstall(home: AgentPaths.CodexHome, runner: any CodexMcpRunner, output: CommandOutput) throws {
        output.emit(home.line)
        let result = try SiftCodexSetup.uninstalling(home: home, runner: runner)
        // The home line already went out, before the uninstall ran, so a refusal names the home.
        for line in result.printed.dropFirst() {
            output.emit(line)
        }
        try exit(result.outcome)
    }

    private static func exit(_ outcome: InstallOutcome) throws {
        guard outcome.failures.isEmpty else { throw ExitCode(1) }
    }
}
