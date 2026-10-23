//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import SiftMCP
import Testing

/// Which hook commands `swift-sure doctor` takes for SwiftSure's own when it looks for traces of an agent's install.
@Suite(.temporaryDirectories)
struct DoctorHookMatchTests {
    /// A probe already closed: the doctor runs nothing, and the scratch the probe made is gone.
    private static func spentProbe() throws -> DoctorProbe {
        let probe = try DoctorProbe(tool: .sift, version: SiftVersion.current, environment: [:])
        probe.close()
        return probe
    }

    /// Whether Claude's doctor finds nothing of SwiftSure's in a `settings.json` whose one `PreToolUse` hook runs `command`.
    private static func holdsNothing(command: String) throws -> Bool {
        let configuration = try TemporaryDirectory.make("doctor-hook-match-claude")
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
        let object: [String: Any] = ["hooks": ["PreToolUse": [["hooks": [["type": "command", "command": command]]]]]]
        try JSONSerialization.data(withJSONObject: object).write(to: configuration.appendingPathComponent("settings.json"))
        return try SiftClaudeSetup.doctors(environment: ["CLAUDE_CONFIG_DIR": configuration.path], probe: spentProbe(), expectedTools: MCPToolCatalog.toolNames).allSatisfy(\.hasNothingInstalled)
    }

    private static func claude(_ configuration: URL) throws -> DoctorClaude {
        try DoctorClaude(environment: ["CLAUDE_CONFIG_DIR": configuration.path], probe: spentProbe(), hooks: SiftClaudeSetup.hooks, server: SiftClaudeSetup.server, expectedTools: MCPToolCatalog.toolNames)
    }

    @Test
    func aCommandWhosePathMerelyContainsTheNameIsNotSifts() throws {
        try #expect(Self.holdsNothing(command: "/Users/sifton/bin/lint.sh"))
    }

    @Test
    func theFormInstallHookWritesIsSifts() throws {
        let command = "\(ShellWord.quoted("/Users/me/Apps With Space/swift-sure")) pre-tool-use"

        try #expect(!Self.holdsNothing(command: command))
    }

    @Test
    func anAbsolutePathToTheBinaryIsSifts() throws {
        try #expect(!Self.holdsNothing(command: "/opt/x/bin/swift-sure pre-tool-use --agent codex"))
    }

    @Test
    func aVersionPinnedNpxPackageIsSiftsAndALongerNameIsNot() throws {
        try #expect(!Self.holdsNothing(command: "npx -y @agulhas-labs/sift@0.1.3 session-start"))
        try #expect(Self.holdsNothing(command: "npx -y @agulhas-labs/sifton@0.1.3 session-start"))
    }

    @Test
    func aPathComponentOrAnArgumentNamedSiftIsNotTheProgram() throws {
        for command in ["cd ~/swift-sure && make", "foo --name swift-sure", "/opt/swift-sure/bin/other pre-tool-use", "/opt/swift-sure/bin/other hook"] {
            try #expect(Self.holdsNothing(command: command), "\(command)")
        }
    }

    @Test
    func theProgramWordIsReadAfterEnvironmentAssignmentsAndExec() throws {
        for command in ["/Users/x/.local/bin/swift-sure stop", "SWIFT_SURE_HOME=/tmp/h exec /Users/x/.local/bin/swift-sure post-tool-use", "\"/path with space/swift-sure\" session-start"] {
            try #expect(!Self.holdsNothing(command: command), "\(command)")
        }
    }

    @Test
    func theSiftBinaryRunningSomethingThatIsNoHookIsNotAHook() throws {
        try #expect(Self.holdsNothing(command: "/Users/x/.local/bin/swift-sure digest ."))
    }

    /// A binary named `swift-sure` under a directory with a space in it, as an older install registered it without quoting.
    private static func withSpacedBinary(_ body: (_ binary: String, _ root: URL) throws -> Void) throws {
        let root = try TemporaryDirectory.make("doctor-hook-match")
        let directory = root.appendingPathComponent("My Tools", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let binary = directory.appendingPathComponent("swift-sure")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try body(binary.path, root)
    }

    @Test
    func theUnquotedSpacedPathAnOlderInstallWroteIsSifts() throws {
        try Self.withSpacedBinary { binary, _ in
            for subcommand in ["pre-tool-use", "session-start"] {
                try #expect(!Self.holdsNothing(command: "\(binary) \(subcommand)"), "\(subcommand)")
            }
        }
    }

    /// The same unquoted shape still counts once its binary is gone, the most broken trace a check for any trace must report.
    @Test
    func theUnquotedSpacedPathCountsAfterItsBinaryIsDeleted() throws {
        try Self.withSpacedBinary { binary, _ in
            try FileManager.default.removeItem(atPath: binary)
            for subcommand in ["pre-tool-use", "session-start"] {
                try #expect(!Self.holdsNothing(command: "\(binary) \(subcommand)"), "\(subcommand)")
            }
            try #expect(Self.holdsNothing(command: "\(binary) digest ."))
        }
    }

    @Test
    func claudeHoldingOnlyTheUnquotedSpacedPathHooksIsNotNothingOfSifts() throws {
        try Self.withSpacedBinary { binary, root in
            let events = SiftClaudeSetup.events
            var hooks: [String: Any] = [:]
            for event in events {
                hooks[event.name] = [["hooks": [["type": "command", "command": "\(binary) \(event.subcommand)"]]]]
            }
            let configuration = root.appendingPathComponent("claude", isDirectory: true)
            try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["hooks": hooks]).write(to: configuration.appendingPathComponent("settings.json"))

            try #expect(!Self.claude(configuration).hasNothingInstalled)
        }
    }
}
