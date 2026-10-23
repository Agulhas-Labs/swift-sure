//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `install` and `uninstall` over what an earlier release registered in Cursor and Codex under its own name: taken out once the current name's is in place, left when it is not, and only when it is this tool's.
@Suite(.temporaryDirectories)
struct CursorCodexLegacyInstallTests {
    private static var oldBinary: String {
        "/opt/old/bin/sift"
    }

    private static var legacyLine: String {
        "an earlier release registered"
    }

    /// Whether `run` printed `line`, whatever it is indented by.
    private static func said(_ run: InstallCommandHarness.Run, _ line: String) -> Bool {
        run.lines.contains { $0.trimmingCharacters(in: .whitespaces) == line }
    }

    private static func server(_ command: String, _ arguments: [String]) -> String {
        let quoted = arguments.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"mcpServers":{"sift":{"command":"\#(command)","args":[\#(quoted)]}}}"#
    }

    private static var legacyCursorHooks: String {
        let hooks = SiftCursorSetup.hooks
        let entries = hooks.hooks.map { #""\#($0.event)":[{"command":"\#(oldBinary) \#(hooks.registeredSubcommand(for: $0))"}]"# }
        return #"{"hooks":{\#(entries.joined(separator: ","))},"version":1}"#
    }

    private static var legacyCodexHooks: String {
        let entries = CodexHooksFile.hooks.map { #""\#($0.event)":[{"matcher":"*","hooks":[{"type":"command","command":"\#(oldBinary) \#($0.subcommand)"}]}]"# }
        return #"{"hooks":{\#(entries.joined(separator: ","))}}"#
    }

    private static let oldServer = (command: oldBinary, arguments: ["mcp"])

    @Test
    func anInstallTakesTheEarlierReleasesCursorServerAndHooksOutOnceItsOwnAreIn() throws {
        let machine = try Machine(cursorServers: Self.server(Self.oldBinary, ["mcp"]), cursorHooks: Self.legacyCursorHooks)

        let run = try machine.install()

        #expect(run.status == 0, "\(run.printed)")
        #expect(try Set(machine.cursorServers().keys) == ["swift-sure"], "\(run.printed)")
        let commands = try machine.cursorCommands()
        #expect(!commands.isEmpty && commands.allSatisfy { $0.contains("swift-sure") && !$0.contains(Self.oldBinary) }, "\(commands)")
        #expect(Self.said(run, "mcp: removed the server sift \(Self.legacyLine) — \(Self.oldBinary) mcp"), "\(run.printed)")
        #expect(Self.said(run, "hooks: removed the earlier release's hooks (sift)"), "\(run.printed)")
    }

    @Test
    func aServerNamedForTheEarlierReleaseThatRunsSomethingElseIsLeftAndUnmentioned() throws {
        let foreign = #"{"hooks":{"preToolUse":[{"command":"/opt/other/helper pre-tool-use --agent cursor"}]},"version":1}"#
        let machine = try Machine(cursorServers: Self.server("/opt/other/helper", ["serve"]), cursorHooks: foreign)

        let run = try machine.install()

        #expect(try Set(machine.cursorServers().keys) == ["sift", "swift-sure"])
        #expect(try machine.cursorCommands().contains("/opt/other/helper pre-tool-use --agent cursor"))
        #expect(!run.printed.contains(Self.legacyLine), "\(run.printed)")
    }

    @Test
    func theEarlierReleasesCursorServerStaysWhileTheCurrentNamesIsHeldByAnotherServer() throws {
        let both = #"{"mcpServers":{"sift":{"command":"\#(Self.oldBinary)","args":["mcp"]},"swift-sure":{"command":"/opt/other/helper","args":["serve"]}}}"#
        let machine = try Machine(cursorServers: both)

        let run = try machine.install()

        #expect(try Set(machine.cursorServers().keys) == ["sift", "swift-sure"])
        #expect(Self.said(run, "mcp: the server sift \(Self.legacyLine) was left — a server named swift-sure runs something else"), "\(run.printed)")
    }

    @Test
    func anInstallTakesTheEarlierReleasesCodexHooksAndServerOutOnceItsOwnAreIn() throws {
        let codex = FakeCodex(others: ["sift": Self.oldServer])
        let machine = try Machine(codex: codex, codexHooks: Self.legacyCodexHooks)

        let run = try machine.install()

        #expect(run.status == 0, "\(run.printed)")
        #expect(codex.calls.map(\.arguments).contains(["mcp", "remove", "sift"]))
        #expect(!codex.calls.map(\.arguments).contains(["mcp", "remove", "swift-sure"]))
        #expect(codex.server(named: "sift") == nil)
        #expect(codex.server?.command == machine.harness.binary)
        let commands = try machine.codexCommands()
        #expect(!commands.isEmpty && commands.allSatisfy { $0.contains("swift-sure") && !$0.contains(Self.oldBinary) }, "\(commands)")
        #expect(Self.said(run, "mcp: removed the server sift \(Self.legacyLine) — \(Self.oldBinary) mcp"), "\(run.printed)")
        #expect(Self.said(run, "hooks: removed the earlier release's hooks (sift)"), "\(run.printed)")
    }

    @Test
    func aCodexServerNamedForTheEarlierReleaseThatRunsSomethingElseIsLeftAndUnmentioned() throws {
        let codex = FakeCodex(others: ["sift": (command: "/opt/other/helper", arguments: ["serve"])])
        let machine = try Machine(codex: codex)

        let run = try machine.install()

        #expect(!codex.calls.map(\.arguments).contains(["mcp", "remove", "sift"]))
        #expect(codex.server(named: "sift")?.command == "/opt/other/helper")
        #expect(!run.printed.contains(Self.legacyLine), "\(run.printed)")
    }

    @Test
    func theEarlierReleasesCodexServerStaysWhileTheCurrentNamesIsHeldByAnotherServer() throws {
        let codex = FakeCodex(server: (command: "/opt/other/helper", arguments: ["serve"]), others: ["sift": Self.oldServer])
        let machine = try Machine(codex: codex)

        let run = try machine.install()

        #expect(!codex.calls.map(\.arguments).contains(["mcp", "remove", "sift"]))
        #expect(Self.said(run, "mcp: the server sift \(Self.legacyLine) was left — a server named swift-sure runs something else"), "\(run.printed)")
    }

    @Test
    func aSecondInstallPrintsNothingAboutTheEarlierRelease() throws {
        let machine = try Machine(codex: FakeCodex(others: ["sift": Self.oldServer]), cursorServers: Self.server(Self.oldBinary, ["mcp"]), cursorHooks: Self.legacyCursorHooks, codexHooks: Self.legacyCodexHooks)
        _ = try machine.install()

        let again = try machine.install()

        #expect(again.status == 0)
        #expect(!again.printed.contains(Self.legacyLine), "\(again.printed)")
        #expect(!again.printed.contains("earlier release"), "\(again.printed)")
    }

    @Test
    func theUninstallTakesTheEarlierReleasesCursorEntriesOut() throws {
        let machine = try Machine(cursorServers: Self.server(Self.oldBinary, ["mcp"]), cursorHooks: Self.legacyCursorHooks)

        let step = SiftUninstall.cursorStep(machine.cursor)

        #expect(step.failure == nil)
        #expect(try machine.cursorServers().isEmpty)
        #expect(try machine.cursorCommands().isEmpty)
        #expect(step.outcome.lines.contains("mcp: removed the server sift \(Self.legacyLine) — \(Self.oldBinary) mcp"), "\(step.outcome.lines)")
    }

    @Test
    func theUninstallHookTakesTheEarlierReleasesCursorEntriesOutAndLeavesAForeignServer() throws {
        let both = #"{"mcpServers":{"sift":{"command":"\#(Self.oldBinary)","args":["mcp"]}}}"#
        let machine = try Machine(cursorServers: both, cursorHooks: Self.legacyCursorHooks)

        let printed = try CursorInstallHookTests.uninstall(machine.cursor)

        #expect(try machine.cursorServers().isEmpty, "\(printed)")
        #expect(try machine.cursorCommands().isEmpty, "\(printed)")
        #expect(!printed.contains("nothing registered"), "\(printed)")
        let foreign = try Machine(cursorServers: Self.server("/opt/other/helper", ["serve"]))
        _ = try CursorInstallHookTests.uninstall(foreign.cursor)
        #expect(try Set(foreign.cursorServers().keys) == ["sift"])
    }

    @Test
    func theUninstallTakesTheEarlierReleasesCodexEntriesOutAndLeavesAForeignServer() throws {
        let codex = FakeCodex(others: ["sift": Self.oldServer])
        let machine = try Machine(codex: codex, codexHooks: Self.legacyCodexHooks)

        let step = SiftUninstall.codexStep(machine.home, runner: codex)

        #expect(step.failure == nil)
        #expect(codex.server(named: "sift") == nil)
        #expect(try machine.codexCommands().isEmpty)
        #expect(step.outcome.lines.contains("mcp: removed the server sift \(Self.legacyLine) — \(Self.oldBinary) mcp"), "\(step.outcome.lines)")

        let other = FakeCodex(others: ["sift": (command: "/opt/other/helper", arguments: ["serve"])])
        let foreign = try Machine(codex: other)
        let left = SiftUninstall.codexStep(foreign.home, runner: other)
        #expect(other.server(named: "sift") != nil)
        #expect(!left.outcome.lines.joined().contains(Self.legacyLine))
    }
}

extension CursorCodexLegacyInstallTests {
    /// A Cursor directory and a Codex home under the machine's home, each made, with the files `cursor` and `codex` name written byte for byte.
    private struct Machine {
        let harness: InstallCommandHarness
        let cursor: URL
        let codexHome: URL

        init(codex: FakeCodex = FakeCodex(), cursorServers: String? = nil, cursorHooks: String? = nil, codexHooks: String? = nil) throws {
            harness = try InstallCommandHarness(onPath: ["codex"], directories: [".cursor", ".codex"], codex: codex)
            cursor = harness.home.appendingPathComponent(".cursor")
            codexHome = harness.home.appendingPathComponent(".codex")
            for (text, url) in [(cursorServers, cursor.appendingPathComponent("mcp.json")), (cursorHooks, cursor.appendingPathComponent("hooks.json")), (codexHooks, codexHome.appendingPathComponent("hooks.json"))] {
                try text.map { try $0.write(to: url, atomically: true, encoding: .utf8) }
            }
        }

        var home: CodexInstall.Home {
            CodexInstall.Home(directory: codexHome, source: "--codex-dir")
        }

        func install() throws -> InstallCommandHarness.Run {
            try harness.run(["--agent", "cursor", "--agent", "codex", "--cursor-dir", cursor.path, "--codex-dir", codexHome.path])
        }

        func cursorServers() throws -> [String: Any] {
            try CursorInstallHookTests.object(at: cursor.appendingPathComponent("mcp.json"))["mcpServers"] as? [String: Any] ?? [:]
        }

        func cursorCommands() throws -> [String] {
            let events = try CursorInstallHookTests.object(at: cursor.appendingPathComponent("hooks.json"))["hooks"] as? [String: [[String: Any]]] ?? [:]
            return events.values.flatMap { $0.compactMap { $0["command"] as? String } }
        }

        func codexCommands() throws -> [String] {
            let data = try Data(contentsOf: codexHome.appendingPathComponent("hooks.json"))
            let events = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["hooks"] as? [String: [[String: Any]]] ?? [:]
            return events.values.flatMap { $0.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } } }
        }
    }
}

extension CursorCodexLegacyInstallTests {
    /// The names of the files in `directory` that carry the earlier release's backup extension.
    private static func earlierBackups(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".bak-sift") }
    }

    @Test
    func anInstallOverLegacyOnlyCursorEntriesBacksUpUnderTheCurrentNameFromThePreRunBytes() throws {
        let machine = try Machine(cursorServers: Self.server(Self.oldBinary, ["mcp"]), cursorHooks: Self.legacyCursorHooks)

        _ = try machine.install()

        #expect(try Self.earlierBackups(in: machine.cursor).isEmpty)
        let backup = try String(contentsOf: machine.cursor.appendingPathComponent("mcp.json.bak-swift-sure"), encoding: .utf8)

        #expect(backup == Self.server(Self.oldBinary, ["mcp"]))
        let hooksBackup = try String(contentsOf: machine.cursor.appendingPathComponent("hooks.json.bak-swift-sure"), encoding: .utf8)
        #expect(hooksBackup == Self.legacyCursorHooks)
    }

    @Test
    func theUninstallOverLegacyOnlyCursorEntriesBacksUpUnderTheCurrentNameFromThePreRunBytes() throws {
        let machine = try Machine(cursorServers: Self.server(Self.oldBinary, ["mcp"]), cursorHooks: Self.legacyCursorHooks)

        _ = SiftUninstall.cursorStep(machine.cursor)

        #expect(try Self.earlierBackups(in: machine.cursor).isEmpty)
        let backup = try String(contentsOf: machine.cursor.appendingPathComponent("mcp.json.bak-swift-sure"), encoding: .utf8)

        #expect(backup == Self.server(Self.oldBinary, ["mcp"]))
    }

    @Test
    func aCodexInstallOverLegacyHooksKeepsThePreInstallFileAsItsBackup() throws {
        let machine = try Machine(codexHooks: Self.legacyCodexHooks)

        _ = try machine.install()

        let backup = try String(contentsOf: machine.codexHome.appendingPathComponent("hooks.json.bak-swift-sure"), encoding: .utf8)

        #expect(backup == Self.legacyCodexHooks)
    }

    @Test
    func legacyCodexHooksWithNoCodexNameTheCommandThatRemovesTheEarlierServer() throws {
        let machine = try Machine(codex: FakeCodex(present: false), codexHooks: Self.legacyCodexHooks)

        let run = try machine.install()

        #expect(run.printed.contains("codex mcp remove sift"), "\(run.printed)")
    }

    @Test
    func aForeignServerHoldingTheCurrentNameIsNotAnInstallToRun() throws {
        let both = #"{"mcpServers":{"sift":{"command":"\#(Self.oldBinary)","args":["mcp"]},"swift-sure":{"command":"/opt/other/helper","args":["serve"]}}}"#
        let cursor = try Machine(cursorServers: both).install()
        let codex = FakeCodex(server: (command: "/opt/other/helper", arguments: ["serve"]), others: ["sift": Self.oldServer])
        let codexRun = try Machine(codex: codex).install()

        for run in [cursor, codexRun] {
            #expect(!run.printed.contains("run: swift-sure install"), "\(run.printed)")
            #expect(run.printed.contains("a server named swift-sure runs something else"), "\(run.printed)")
        }
    }

    @Test
    func anInstallThatOnlyTookTheEarlierCodexServerOutDoesNotSayNothingWasToDo() throws {
        let codex = FakeCodex(others: ["sift": Self.oldServer])
        let machine = try Machine(codex: codex)
        _ = try machine.install()
        _ = try codex.run(["mcp", "add", "sift", "--", Self.oldBinary, "mcp"], home: machine.codexHome)

        let run = try machine.install()

        #expect(run.printed.contains("removed the server sift"), "\(run.printed)")
        #expect(!run.printed.contains("Codex: already installed, nothing to do"), "\(run.printed)")
    }
}
