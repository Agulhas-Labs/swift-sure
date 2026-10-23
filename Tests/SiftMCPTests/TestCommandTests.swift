//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// Covers `swift-sure test`'s argument validation, where `--analyse` refuses every flag that describes a build or a run it will not do.
@Suite(.temporaryDirectories)
struct TestCommandTests {
    /// `--analyse`'s answer, through the CLI layer, opens with the freshness header and follows it with the sections in ``TestAnalysisRenderer/render(_:)``'s own order — unpinned before this test.
    @Test
    func theAnswerOpensWithTheHeaderAndKeepsTheRenderersSectionOrder() async throws {
        let root = try TemporaryDirectory.make("test-analyse-header")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("AlphaTests"),
            withIntermediateDirectories: true
        )
        try """
        name: Gizmo
        targets:
          AlphaTests:
            type: bundle.unit-test
            platform: iOS
            sources:
              - path: AlphaTests
        """.write(to: root.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        try """
        import XCTest

        final class StringHelperTests: XCTestCase {
            func testJoining() {
                XCTAssertTrue(true)
            }
        }
        """.write(to: root.appendingPathComponent("AlphaTests/StringHelperTests.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("TestPlans"),
            withIntermediateDirectories: true
        )
        try """
        {"version":1,"testTargets":[{"skippedTests":["StringHelperTests"],
        "target":{"containerPath":"container:Gizmo.xcodeproj","identifier":"30E1","name":"AlphaTests"}}]}
        """.write(to: root.appendingPathComponent("TestPlans/Default.xctestplan"), atomically: true, encoding: .utf8)
        for arguments in [["init", "-b", "main"], ["add", "-A"], ["-c", "user.email=t@example.com", "-c", "user.name=Tester", "commit", "-m", "fixture"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = root
            try process.run()
            process.waitUntilExit()
        }

        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let command = try TestCommand.parse(["--analyse", "--root", root.resolvingSymlinksInPath().path])
        let (answer, _) = try await command.analysis(workingDirectory: root, registry: registry)

        let lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first?.hasPrefix("tree:") == true)
        let planLine = try #require(lines.firstIndex { $0.contains("test plan") && $0.contains("read live off disk") })
        let headlineLine = try #require(lines.firstIndex { $0.contains("swift-sure test --analyse —") })
        let tableHeaderLine = try #require(lines.firstIndex { $0.contains("declared  in a plan  runs  never runs  conditional") })
        let honouredLine = try #require(lines.firstIndex { $0 == "plan exclusions that work and leave no trace (1)" })
        #expect(planLine < headlineLine)
        #expect(headlineLine < tableHeaderLine)
        #expect(tableHeaderLine < honouredLine)
    }

    /// `--analyse` refuses a run's flag by name, in the one sentence every such refusal shares, before anything is opened.
    ///
    /// `--guard-shards` among them: `run()` answers `--analyse` before it reads the watcher's flag, so a pair it accepted would drop the flag without a word.
    @Test(arguments: [
        (["--scheme", "Demo"], "--scheme"),
        (["--guard-shards", "run-1"], "--guard-shards"),
        (["--shard-timeout", "60"], "--shard-timeout"),
    ])
    func analyseRefusesARunsFlagByName(extra: [String], flag: String) {
        #expect(
            Self.refusal(["--analyse"] + extra)
                == "--analyse and \(flag) ask for two different things: --analyse reads the index and the test plans and starts no build, boots no simulator and runs no test, so there is nothing for \(flag) to name. Drop one of the two."
        )
    }

    /// A command nobody injected a store into leases into `.simwalk/leases` under the account's home, the machine's shared store.
    @Test
    func theDefaultLeaseStoreIsTheAccountsSimwalkStore() throws {
        let home = try String(cString: #require(getpwuid(getuid())).pointee.pw_dir)

        let command = try TestCommand.parse(["--sweep"])

        #expect(command.leases?.directory.path == "\(home)/.simwalk/leases")
    }

    /// `--sweep` deletes every device a dead run of this checkout recorded and names each one it deleted, through the command's own output and a `simctl` that touches nothing real.
    @Test
    func sweepDeletesADeadRunsRecordedDevicesAndNamesEachOne() async throws {
        let directory = try TemporaryDirectory.make("test-sweep")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", "-q", "-b", "main"]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        let root = try #require(GitContext.discoverRoot(from: directory))
        let prefix = try ShardLedger.devicePrefix(in: root)
        let udids = ["11111111-2222-3333-4444-555555555555", "66666666-7777-8888-9999-000000000000"]
        var ledger = try ShardLedger(repositoryRoot: root, runID: "0f9e8d7c", prefix: prefix, owner: ShardLedger.Identity(pid: 4711, startMicroseconds: 111), started: { _ in nil })
        var names: [String] = []
        for (index, udid) in udids.enumerated() {
            try names.append(ledger.recordIntent(shard: index))
            try ledger.record(udid: udid, forShard: index)
        }
        let deleted = RecordedOutput()
        let recorded = RecordedOutput()
        var command = try TestCommand.parse(["--sweep"])
        command.output = recorded.output
        command.startingDirectory = directory
        command.leases = ShardLeases(directory: directory.appendingPathComponent("leases"))
        command.simctl = { _, arguments in
            if arguments.contains("delete"), let udid = arguments.last {
                deleted.output.emit(udid)
            }
            return Subprocess.Output(succeeded: true, standardOutput: arguments.contains("list") ? #"{ "devices": {} }"# : "")
        }

        try await command.run()

        #expect(deleted.printed == udids.map { "\($0)\n" }.joined())
        #expect(recorded.printed == """
        ✔ swift-sure test --sweep — deleted 2 simulators left by runs of this checkout that are no longer running
          deleted \(names[0]) \(udids[0])
          deleted \(names[1]) \(udids[1])

        """)
        #expect(!FileManager.default.fileExists(atPath: ledger.directory.path))
    }

    /// `--sweep` runs nothing, so it refuses a run's flag, `--analyse` and a pass-through by name, before anything is opened.
    @Test(arguments: [
        (["--shards", "2"], "--shards"),
        (["--shard-timeout", "60"], "--shard-timeout"),
        (["--analyse"], "--analyse"),
        (["--", "-derivedDataPath", "build"], "everything after --"),
    ])
    func sweepRefusesARunsFlagByName(extra: [String], flag: String) {
        #expect(
            Self.refusal(["--sweep"] + extra)
                == "--sweep and \(flag) ask for two different things: --sweep deletes the simulators left by this checkout's runs that are no longer running, and builds, boots and runs nothing. Drop one of the two."
        )
    }

    /// `--stock` chooses how simulators boot, which `--analyse` never does.
    @Test
    func analyseRefusesStock() {
        #expect(
            Self.refusal(["--analyse", "--stock"])
                == "--analyse and --stock ask for two different things: --analyse reads the index and the test plans and starts no build, boots no simulator and runs no test, so there is nothing for --stock to name. Drop one of the two."
        )
    }

    /// `--stock` chooses how simulators boot, which `--sweep` never does.
    @Test
    func sweepRefusesStock() {
        #expect(
            Self.refusal(["--sweep", "--stock"])
                == "--sweep and --stock ask for two different things: --sweep deletes the simulators left by this checkout's runs that are no longer running, and builds, boots and runs nothing. Drop one of the two."
        )
    }

    /// A SwiftPM package run boots no simulator, so `--stock` has nothing to choose there.
    @Test
    func aPackageRunRefusesStock() throws {
        let directory = try TemporaryDirectory.make("test-stock-package")
        try Data().write(to: directory.appendingPathComponent("Package.swift"))
        let command = try TestCommand.parse(["--stock"])

        do {
            _ = try command.packageRun(in: directory)
            Issue.record("expected --stock to be refused in a package")
        } catch {
            #expect(TestCommand.message(for: error) == "--stock chooses how simulators boot, and a SwiftPM package run boots none. Drop --stock.")
        }
    }

    /// `--root` names the package, so a command started elsewhere shards that package's suite and not the working directory's.
    @Test
    func rootNamesThePackageTheCommandRunsIn() throws {
        let directory = try TemporaryDirectory.make("test-root-package")
        try Data().write(to: directory.appendingPathComponent("Package.swift"))
        let command = try TestCommand.parse(["--root", directory.path])

        let chosen = try command.commandDirectory()

        #expect(chosen.standardizedFileURL.resolvingSymlinksInPath() == directory.standardizedFileURL.resolvingSymlinksInPath())
        #expect(chosen.standardizedFileURL.resolvingSymlinksInPath() != URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath())
    }

    /// A `--root` that is not a directory is refused at once, naming it.
    @Test
    func rootThatIsNotADirectoryIsRefused() throws {
        let directory = try TemporaryDirectory.make("test-root-missing")
        let missing = directory.appendingPathComponent("absent").path
        let command = try TestCommand.parse(["--root", missing])

        do {
            _ = try command.commandDirectory()
            Issue.record("expected a missing --root to be refused")
        } catch {
            #expect(TestCommand.message(for: error) == "\(ProductName.current.binary) test --root: \(missing) is not a directory.")
        }
    }

    /// `--animations` chooses how the app under UI test launches, which `--analyse` never does.
    @Test
    func analyseRefusesAnimations() {
        #expect(
            Self.refusal(["--analyse", "--animations"])
                == "--analyse and --animations ask for two different things: --analyse reads the index and the test plans and starts no build, boots no simulator and runs no test, so there is nothing for --animations to name. Drop one of the two."
        )
    }

    /// `--animations` chooses how the app under UI test launches, which `--sweep` never does.
    @Test
    func sweepRefusesAnimations() {
        #expect(
            Self.refusal(["--sweep", "--animations"])
                == "--sweep and --animations ask for two different things: --sweep deletes the simulators left by this checkout's runs that are no longer running, and builds, boots and runs nothing. Drop one of the two."
        )
    }

    /// A SwiftPM package run launches no app, so `--animations` has nothing to keep on there.
    @Test
    func aPackageRunRefusesAnimations() throws {
        let directory = try TemporaryDirectory.make("test-animations-package")
        try Data().write(to: directory.appendingPathComponent("Package.swift"))
        let command = try TestCommand.parse(["--animations"])

        do {
            _ = try command.packageRun(in: directory)
            Issue.record("expected --animations to be refused in a package")
        } catch {
            #expect(TestCommand.message(for: error) == "--animations keeps animations on in a simulator app under UI test, and a SwiftPM package run launches no app. Drop --animations.")
        }
    }

    /// `--shards` above ``ShardPlanner/maximumShards`` is refused with the exact reason before anything is launched.
    @Test
    func shardsAboveTheMaximumAreRefused() throws {
        let command = try TestCommand.parse(["--scheme", "Demo", "--device", "iPhone 17", "--shards", "17"])
        let directory = try TemporaryDirectory.make("test-shards-refused")

        #expect(
            Self.requestRefusal(command, in: directory)
                == "--shards 17 is more than swift-sure will ever plan onto: each shard is a booted simulator — roughly 2–4 GB and a core or two — so 16 is the most, and this host's own default never goes above 6."
        )
    }

    /// `--shards 16`, the maximum, is accepted: validation moves past the bound check to the next requirement (a git repository) rather than refusing it.
    @Test
    func shardsAtTheMaximumAreAccepted() throws {
        let command = try TestCommand.parse(["--scheme", "Demo", "--device", "iPhone 17", "--shards", "16"])
        let directory = try TemporaryDirectory.make("test-shards-accepted")

        #expect(
            Self.requestRefusal(command, in: directory)
                == "swift-sure test runs inside a git repository: the ledger that says which simulators to delete, the shard logs and the test durations all live in that repository's .swift-sure/."
        )
    }

    /// `--shard-timeout` below the sane minimum is refused with the exact reason before anything is launched.
    @Test
    func shardTimeoutBelowTheMinimumIsRefused() throws {
        let command = try TestCommand.parse(["--scheme", "Demo", "--device", "iPhone 17", "--shard-timeout", "29"])
        let directory = try TemporaryDirectory.make("test-shard-timeout-refused")

        #expect(
            Self.requestRefusal(command, in: directory)
                == "--shard-timeout 29 is below 30: a bound that low fires on a healthy shard before xcodebuild has even launched, and costs the whole suite it was given."
        )
    }

    /// `--shard-timeout` at the minimum is accepted, and lowers the floor ``ShardRunner`` reads a predicted shard against.
    @Test
    func shardTimeoutAtTheMinimumLowersTheFloor() throws {
        let command = try TestCommand.parse(["--scheme", "Demo", "--device", "iPhone 17", "--shard-timeout", "30"])
        let directory = try TemporaryDirectory.make("test-shard-timeout-accepted")

        #expect(
            Self.requestRefusal(command, in: directory)
                == "swift-sure test runs inside a git repository: the ledger that says which simulators to delete, the shard logs and the test durations all live in that repository's .swift-sure/."
        )
    }

    /// A git that does not answer for the directory is refused as that, never as the directory being outside a repository.
    @Test
    func aGitThatDoesNotAnswerIsNotRefusedAsNoRepository() async throws {
        let root = try TemporaryDirectory.make("test-git-unanswered")
        let fifo = try Self.blockGitReads(in: root)
        defer { Self.release(fifo) }

        let answered = await Deadline.within(seconds: 20) { () -> String in
            guard let command = try? TestCommand.parse(["--scheme", "Demo", "--device", "iPhone 17"]) else { return "the arguments did not parse" }
            return Self.requestRefusal(command, in: root) ?? "no refusal"
        }
        Self.release(fifo)
        let refusal = try #require(answered, "the request was still waiting on git after 20 seconds: the call has no bound")

        #expect(refusal.contains("git did not answer within"), "\(refusal)")
        #expect(!refusal.contains("swift-sure test runs inside a git repository"), "\(refusal)")
    }

    /// Makes `root` a repository whose config includes a FIFO nobody writes, so `git rev-parse` blocks there until its bound ends it; answers the FIFO's path.
    private static func blockGitReads(in root: URL) throws -> String {
        let git = root.appendingPathComponent(".git", isDirectory: true)
        for sub in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: git.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/main\n".utf8).write(to: git.appendingPathComponent("HEAD"))
        let fifo = root.appendingPathComponent("config.fifo").path
        guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try Data("[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n".utf8).write(to: git.appendingPathComponent("config"))
        return fifo
    }

    /// Opens the FIFO's write end without blocking, which releases any git still blocked reading it, then closes it.
    private static func release(_ fifo: String) {
        let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// What `command.request(in:)` refuses with, read as the sentence a person sees.
    private static func requestRefusal(_ command: TestCommand, in directory: URL) -> String? {
        do {
            _ = try command.request(in: directory)
            return nil
        } catch {
            return TestCommand.message(for: error)
        }
    }

    /// What parsing these arguments refuses with, or `nil` where it accepts them.
    ///
    /// Read as the sentence a person sees: a parse wraps a validation failure in ArgumentParser's own error, and the wording is what is pinned.
    private static func refusal(_ arguments: [String]) -> String? {
        do {
            _ = try TestCommand.parse(arguments)
            return nil
        } catch {
            return TestCommand.message(for: error)
        }
    }
}
