//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
@testable import SiftCore
import Testing

/// `swift-sure install`'s family step: the other Fieldwork tools' installs, run once, into the agents SwiftSure installed into.
@Suite(.temporaryDirectories)
struct InstallFamilyTests {
    @Test
    func noMemberFoundPrintsNoFamilyLineAndExitsAsSiftDoes() throws {
        let setup = try Setup(present: false)
        let launcher = Launcher()

        let run = try setup.run(["--agent", "claude"], launcher: launcher)

        #expect(run.status == 0)
        #expect(!run.printed.contains("family:"))
        #expect(launcher.all.isEmpty)
    }

    @Test
    func aMemberFoundIsAnnouncedAndStartedForTheAgentsSiftInstalledInto() throws {
        let setup = try Setup(present: true)
        let launcher = Launcher()
        let simwalk = setup.memberDirectory.appendingPathComponent("simwalk").path

        let run = try setup.run(["--agent", "claude"], launcher: launcher)

        #expect(run.status == 0)
        #expect(launcher.all == [Launched(executable: simwalk, arguments: ["install", "--agent", "claude", "--yes"])])
        #expect(run.printed.contains("family: running simwalk install --agent claude --yes"))
    }

    @Test
    func aMemberThatExitsNonzeroIsReportedAndMakesTheInstallExitOne() throws {
        let setup = try Setup(present: true)

        let run = try setup.run(["--agent", "claude"], launcher: Launcher(status: 3))

        #expect(run.status == 1)
        #expect(run.printed.contains("family: simwalk install exited 3"))
    }

    @Test
    func nothingLaunchesWhereAFamilyInstallIsAlreadyRunning() throws {
        let setup = try Setup(present: true)
        let launcher = Launcher()

        let run = try setup.run(["--agent", "claude"], launcher: launcher, extraEnvironment: [Family.environmentVariable: "simwalk"])

        #expect(run.status == 0)
        #expect(launcher.all.isEmpty)
        #expect(!run.printed.contains("family:"))
    }

    @Test
    func aDryRunPassesDryRunOn() throws {
        let setup = try Setup(present: true)
        let launcher = Launcher()

        let run = try setup.run(["--agent", "claude", "--dry-run"], launcher: launcher)

        #expect(run.status == 0)
        #expect(launcher.all.map(\.arguments) == [["install", "--agent", "claude", "--yes", "--dry-run"]])
    }

    @Test
    func siftsOwnFailureStillRunsTheStepAndExitsOne() throws {
        let setup = try Setup(present: true)
        let launcher = Launcher()
        let claude = FakeClaude(config: setup.harness.home.appendingPathComponent(".claude.json"), addSucceeds: false)

        let run = try setup.run(["--agent", "claude"], launcher: launcher, claude: claude)

        #expect(run.status == 1)
        #expect(launcher.all.count == 1)
    }

    @Test
    func aMemberThatCannotBeStartedIsReportedAndMakesTheInstallExitOne() throws {
        struct Refused: Error, CustomStringConvertible {
            var description: String {
                "refused to start"
            }
        }
        let setup = try Setup(present: true)
        let launcher = Launcher(failure: Refused())

        let run = try setup.run(["--agent", "claude"], launcher: launcher)

        #expect(run.status == 1)
        #expect(run.printed.contains("family: simwalk install could not be started: refused to start"), "\(run.printed)")
    }

    @Test
    func everyAgentSiftInstalledIntoIsPassedOnInOrder() throws {
        let setup = try Setup(present: true, onPath: ["claude", "codex"])
        let launcher = Launcher()

        let run = try setup.run(["--agent", "claude", "--agent", "codex"], launcher: launcher)

        #expect(run.status == 0, "\(run.printed)")
        #expect(launcher.all.map(\.arguments) == [["install", "--agent", "claude", "--agent", "codex", "--yes"]])
    }

    @Test
    func installingIntoNothingLaunchesNothing() throws {
        let setup = try Setup(present: true)
        let launcher = Launcher()

        let run = try setup.run([], launcher: launcher)

        #expect(launcher.all.isEmpty)
        #expect(!run.printed.contains("family:"))
    }
}

extension InstallFamilyTests {
    /// One launch a test recorded.
    struct Launched: Equatable {
        let executable: String
        let arguments: [String]
    }

    /// Records every launch and answers `status`.
    final class Launcher: @unchecked Sendable {
        private let lock = NSLock()
        private var launches: [Launched] = []
        let status: Int32
        let failure: (any Error)?

        init(status: Int32 = 0, failure: (any Error)? = nil) {
            self.status = status
            self.failure = failure
        }

        var all: [Launched] {
            lock.withLock { launches }
        }

        var launch: Family.Launch {
            { executable, arguments, _ in
                self.lock.withLock { self.launches.append(Launched(executable: executable, arguments: arguments)) }
                if let failure = self.failure {
                    throw failure
                }
                return self.status
            }
        }
    }

    /// A scratch machine with `claude` found, whose PATH holds a directory with an executable `simwalk` when `present` says so.
    private struct Setup {
        let harness: InstallCommandHarness
        let memberDirectory: URL

        init(present: Bool, onPath: Set<String> = ["claude"]) throws {
            harness = try InstallCommandHarness(onPath: onPath)
            memberDirectory = try TemporaryDirectory.make("family-member")
            if present {
                let script = memberDirectory.appendingPathComponent("simwalk")
                try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            }
        }

        func run(_ arguments: [String], launcher: Launcher, extraEnvironment: [String: String] = [:], claude: FakeClaude? = nil) throws -> InstallCommandHarness.Run {
            var environment = harness.environment
            environment["PATH"] = memberDirectory.path
            environment.merge(extraEnvironment) { _, new in new }
            let base = harness.machine
            let machine = AgentDetection.Machine(environment: environment, applications: harness.applications, pathLookup: base.pathLookup, fileExists: base.fileExists)
            let recorded = RecordedOutput()
            var command = try InstallCommand.parse(arguments)
            command.output = recorded.output
            command.machine = machine
            command.prompt = AllowRunPrompt(isInteractive: false, ask: { _ in nil })
            command.claude = claude ?? harness.claude
            command.codex = harness.codex
            command.arguments = [harness.binary, "install"] + arguments
            command.executable = harness.binary
            command.familyLaunch = launcher.launch
            var status: Int32 = 0
            do {
                try command.run()
            } catch let exit as ExitCode {
                status = exit.rawValue
            }
            return InstallCommandHarness.Run(printed: recorded.printed, status: status, asked: [])
        }
    }
}
