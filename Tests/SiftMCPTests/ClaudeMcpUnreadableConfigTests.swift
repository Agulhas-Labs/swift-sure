//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// A dry run names a Claude Code config that is there and cannot be read as a JSON object as refused, never as holding no server.
@Suite(.temporaryDirectories)
struct ClaudeMcpUnreadableConfigTests {
    @Test
    func aDryRunSaysAnUnparseableConfigWouldBeRefusedNotWritten() throws {
        let machine = try InstallCommandHarness(onPath: ["claude", "codex"], directories: [".claude", ".cursor"])
        let config = AgentPaths.claudeConfig(environment: machine.environment)
        try Data("not json {".utf8).write(to: config)
        let target = try #require(AgentDetection.detect(machine.machine, tool: .sift).finding(.claude).targets.first { $0.url.path == config.path })

        let run = try machine.run(["--dry-run"])

        #expect(run.status == 0)
        #expect(run.lines.contains("    would be refused \(config.path) (\(target.what)) — could not be read as a JSON object"), "\(run.printed)")
        #expect(!run.lines.contains("    would write \(config.path) (\(target.what))"))
        #expect(run.lines.contains("Claude Code MCP server: would be refused — \(config.path) could not be read as a JSON object"), "\(run.printed)")
    }
}
