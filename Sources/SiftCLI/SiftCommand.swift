//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SiftCore

/// The `swift-sure` root command and the subcommands it registers.
@main
struct SiftCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: ProductName.current.binary,
            abstract: "A Swift toolkit for AI coding agents: an index of your code, builds and tests that tell the truth, and checks on every change.",
            version: SiftVersion.current,
            subcommands: [
                InitCommand.self,
                IndexCommand.self,
                StatusCommand.self,
                HelpCommand.self,
                DigestCommand.self,
                WhereCommand.self,
                SearchCommand.self,
                SimilarCommand.self,
                DupesCommand.self,
                StringsCommand.self,
                AffectedCommand.self,
                DiffCommand.self,
                CheckupCommand.self,
                RunCommand.self,
                BuildCommand.self,
                TestCommand.self,
                ReconcileCommand.self,
                ResetCommand.self,
                UsageCommand.self,
                FlakesCommand.self,
                AuditCommand.self,
                ReportCommand.self,
                ReplayHookCommand.self,
                ScanDumpCommand.self,
                MCPCommand.self,
                ServersCommand.self,
                SessionStartCommand.self,
                PreToolUseCommand.self,
                PostToolUseCommand.self,
                StopCommand.self,
                InstallCommand.self,
                DoctorCommand.self,
                InstallHookCommand.self,
                UninstallHookCommand.self,
                UninstallCommand.self,
            ]
        )
    }

    /// ArgumentParser's own entry point, with one line added under the usage error for a lone option-looking query.
    static func main() async {
        do {
            var command = try await asyncParseAsRoot(nil)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            let code = exitCode(for: error)
            if code != .success, let hint = DashQueryHint.line(for: Array(CommandLine.arguments.dropFirst())) {
                FileHandle.standardError.write(Data("\(fullMessage(for: error))\n\(hint)\n".utf8))
                exit(withError: code)
            }
            exit(withError: error)
        }
    }
}
