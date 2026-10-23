//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// A git that cannot finish is ended and reaped, and the answer is the one an unreadable repository gets.
///
/// The fixture is a repository whose `.git/config` has `include.path` naming a FIFO nobody writes: `git rev-parse` blocks opening it for good. Each test gives itself a deadline of its own on a thread, because the failure this pins is a call that never returns, and a test that hangs forever reports nothing.
@Suite(.temporaryDirectories)
struct GitChildBoundTests {
    /// The longest a hook may take: its own timeout is 8 seconds, so an answer has to come well inside them.
    private static let hookBudget: TimeInterval = 5

    /// How long a call that puts several questions to a git that never answers is waited for: each is ended at its own 2-second bound, so only a call with no bound at all misses it.
    private static let unansweredBudget: TimeInterval = 30

    /// How long a bulk read is waited for: well past its 3-second fixture delay and inside the 60-second bulk bound, so machine load cannot decide the test.
    private static let bulkBudget: TimeInterval = 30

    /// Runs `body` on a thread of its own and waits `budget` for it; `nil` where it had not returned.
    private static func within<Result: Sendable>(_ budget: TimeInterval = hookBudget, _ body: @escaping @Sendable () -> Result) -> Result? {
        let box = Box<Result>()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = body()
            finished.signal()
        }
        thread.start()
        return finished.wait(timeout: .now() + budget) == .success ? box.value : nil
    }

    /// The hook's first git call comes back, as a repository git cannot read, inside the hook's budget.
    @Test
    func aGitBlockedOnAFifoConfigIsAnsweredAsNoRepository() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-child-bound"))
        defer { fixture.release() }
        let root = fixture.root
        let started = Date()

        let answered = Self.within { GitContext.spawnedRoot(from: root, within: ChildDeadline.git) }
        fixture.release()

        let result = try #require(answered, "git is still blocked on the FIFO after \(Self.hookBudget) seconds: the call has no bound")

        #expect(result == nil)
        #expect(Date().timeIntervalSince(started) < Self.hookBudget)
    }

    /// Root resolution, the engine, `reset` and both set-aside entry points refuse such a repository as unanswered, never in the not-a-repository wording a caller would act on.
    @Test(arguments: ["resolver", "engine", "reset", "set-aside", "restore"])
    func aGitThatDoesNotAnswerIsNotToldAsNoRepository(asking: String) throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered"))
        defer { fixture.release() }

        let root = fixture.root

        let answered = Self.within(Self.unansweredBudget) { () -> String in
            do {
                switch asking {
                case "resolver": _ = try RootResolver.resolve(directory: root, registry: nil, probing: nil)
                case "engine": _ = try SiftEngine(directory: root)
                case "reset": _ = try SiftEngine.reset(directory: root)
                case "set-aside": _ = try SetAsideSession.begin(pathspecs: ["."], from: root)
                default: _ = try SetAsideSession.restoreAbandoned(in: root)
                }
                return "did not throw"
            } catch let error as EngineError {
                return error.description
            } catch {
                return "not an EngineError: \(error)"
            }
        }
        fixture.release()
        let text = try #require(answered, "\(asking) was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        #expect(text.contains("git did not answer within"), "\(text)")
        #expect(!text.contains("is not inside a git repository"), "\(text)")
    }

    /// A run asking whether set-aside changes are out of such a tree is refused, in the unanswered wording, rather than let through as though none were.
    @Test
    func aGitThatDoesNotAnswerIsARefusalToRun() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered-refusal"))
        defer { fixture.release() }

        let root = fixture.root

        let answered = Self.within(Self.unansweredBudget) { SetAsideSession.refusal(for: root)?.description ?? "no refusal" }
        fixture.release()
        let text = try #require(answered, "the refusal was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        #expect(text != "no refusal", "a run went ahead over a tree git did not answer for")
        #expect(text.hasPrefix("swift-sure run --without: git did not answer within"), "\(text)")
    }

    /// A discovery bound for the scope hands the unanswered git on as that, and does not remember it as no repository: the same directory is asked again, and again goes unanswered.
    @Test
    func aBoundDiscoveryCarriesAnUnansweredGitAndForgetsIt() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered-bound"))
        defer { fixture.release() }

        let root = fixture.root

        let answered = Self.within(Self.unansweredBudget) { () -> BoundAnswers in
            RootDiscovery.$current.withValue(RootDiscovery()) {
                func asked() -> String {
                    do {
                        _ = try GitContext.enclosingRoot(from: root)
                        return "answered"
                    } catch let error as EngineError {
                        return error.description
                    } catch {
                        return "not an EngineError: \(error)"
                    }
                }
                return BoundAnswers(discovered: GitContext.discoverRoot(from: root) == nil, first: asked(), second: asked())
            }
        }
        fixture.release()
        let result = try #require(answered, "the bound discovery was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        #expect(result.discovered)
        #expect(result.first.contains("git did not answer within"), "\(result.first)")
        #expect(result.second.contains("git did not answer within"), "the second ask was answered from memory: \(result.second)")
    }

    /// The overrunning child is gone from the process table afterwards: signalled and reaped, not left for the hook's exit to orphan.
    @Test
    func theOverrunningChildIsReaped() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-child-reaped"))
        defer { fixture.release() }
        let root = fixture.root

        let outcome = Self.within { () -> Reaped in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["rev-parse", "--show-toplevel"]
            process.currentDirectoryURL = root
            process.environment = GitContext.readEnvironment()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exited = DispatchSemaphore(value: 0)
            let watch = ChildDeadline.Watch(process, within: 0.5)
            process.terminationHandler = { _ in
                watch.finish()
                exited.signal()
            }
            guard (try? process.run()) != nil else { return Reaped(pid: 0, timedOut: false, gone: false) }
            watch.arm()
            exited.wait()
            let pid = process.processIdentifier
            let gone = kill(pid, 0) == -1 && errno == ESRCH
            return Reaped(pid: pid, timedOut: watch.timedOut, gone: gone)
        }
        fixture.release()

        let result = try #require(outcome, "the child was still running \(Self.hookBudget) seconds on")

        #expect(result.pid > 0)
        #expect(result.timedOut)
        #expect(result.gone, "pid \(result.pid) is still in the process table after the deadline")
    }

    /// `stop` ends a child that ignores `SIGTERM` with `SIGKILL`, and does not return before it is reaped.
    @Test
    func aChildIgnoringSigtermIsKilledAndReaped() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; while :; do sleep 1; done"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        defer {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
        usleep(200_000)

        ChildDeadline.stop(process)

        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    /// Nothing of the caller's repository reaches git: every `GIT_*` variable is dropped, bar the one that turns off optional locks.
    @Test
    func theEnvironmentGitIsGivenCarriesNoGitVariable() {
        let polluted = ["GIT_DIR": "/elsewhere/.git", "GIT_INDEX_FILE": "/elsewhere/index", "GIT_WORK_TREE": "/elsewhere", "PATH": "/usr/bin"]
        #expect(ProcessEnvironment.withoutGit(from: polluted).keys.sorted() == ["PATH"])

        let given = GitContext.readEnvironment().keys.filter { $0.hasPrefix("GIT_") }
        #expect(given == ["GIT_OPTIONAL_LOCKS"])
    }

    /// A bulk read past the small-query bound still succeeds: the runner given `gitBulk` waits out a child that takes 3 seconds, and the same child under `git` is cut off at 2.
    @Test
    func aBulkReadSlowerThanTheSmallBoundStillSucceeds() throws {
        let root = try TemporaryDirectory.make("git-child-bulk-runner")
        let slow = ["-c", "alias.slow=!sleep 3 && echo ok", "slow"]

        let bulk = try GitContext.run(arguments: slow, in: root, within: ChildDeadline.gitBulk)

        #expect(bulk.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
        #expect(throws: GitError.self) {
            try GitContext.run(arguments: slow, in: root, within: ChildDeadline.git)
        }
    }

    /// The bound a defaulted read takes is the one widened for the root its directory lies under, and nowhere else: a read naming no bound, in a directory under a widened root, waits out a child that takes 3 seconds, which the production two seconds would cut off; a directory beside it that nobody widened keeps those two seconds.
    ///
    /// The root is widened in the spelling `$TMPDIR` gives it (`/var/…`) and read in the resolved one (`/private/var/…`), as the code under test sees it.
    @Test
    func aDefaultedReadTakesTheBoundWidenedForItsRootAndNoOther() throws {
        let root = try TemporaryDirectory.make("git-child-widened")
        let beside = try TemporaryDirectory.make("git-child-not-widened")
        ChildDeadline.widenGitReads(under: root, to: 120)
        let inside = root.resolvingSymlinksInPath().appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: false)
        let slow = ["-c", "alias.slow=!sleep 3 && echo ok", "slow"]

        let defaulted = try GitContext.run(arguments: slow, in: inside)

        #expect(defaulted.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
        #expect(ChildDeadline.gitRead(in: beside) == ChildDeadline.git)
        #expect(ChildDeadline.git == 2)
    }

    /// The caller, not only the runner: `dirtyFiles` is a bulk read, and a repository whose `git status` takes 3 seconds still answers it.
    ///
    /// The slowness is a clean filter, which runs under the fsmonitor hardening: `A.swift` is rewritten with the same content, so its stat data differs from the index's and status runs the filter to compare; the untracked `B.swift` is the change the answer names. A control times a plain status in the same repository, so the test cannot pass on a status that is fast.
    @Test
    func theDirtySetOfARepositoryWhoseStatusTakesThreeSecondsIsStillRead() throws {
        let root = try TemporaryDirectory.make("git-child-bulk-caller")
        try TestSources.runGit(["init", "-q"], in: root)
        try #require(ChildDeadline.gitRead(in: root) == ChildDeadline.git, "the repository's reads are widened, so a caller that dropped its bulk bound would pass")
        try #require(GitContext.spawnedRoot(from: root, within: ChildDeadline.gitBulk)?.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path, "the fixture repository is not the temporary directory")
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid"]
        let source = root.appendingPathComponent("A.swift")
        try Data("struct A {}\n".utf8).write(to: source)
        try Data("*.swift filter=slow\n".utf8).write(to: root.appendingPathComponent(".gitattributes"))
        try TestSources.runGit(["add", "."], in: root)
        try TestSources.runGit(identity + ["commit", "-q", "-m", "one"], in: root)
        let filter = root.appendingPathComponent("slow-filter.sh")
        try Data("#!/bin/sh\nsleep 3.5\ncat\n".utf8).write(to: filter)
        #expect(chmod(filter.path, 0o755) == 0)
        try TestSources.runGit(["config", "filter.slow.clean", filter.path], in: root)
        try Data("struct A {}\n".utf8).write(to: source)
        try Data("struct B {}\n".utf8).write(to: root.appendingPathComponent("B.swift"))

        let control = Date()
        _ = try TestSources.runGit(["-c", "core.fsmonitor=false", "--no-optional-locks", "status", "--porcelain"], in: root)
        let took = Date().timeIntervalSince(control)
        try #require(took >= 3, "a plain status took \(took) seconds: the fixture is not slow, so the bulk deadline is not exercised")

        let changes = try GitContext(repoRoot: root).dirtySwiftFiles()

        #expect(changes.map(\.path) == ["B.swift"])
    }

    /// A descendant of git that holds its stdout does not hold the call: a 2 second call whose alias leaves a `sleep 30` on the pipe answers inside the bound and its grace, and the sleep is ended with git's group.
    @Test
    func aDescendantHoldingTheStreamsIsEndedWithTheGroup() throws {
        let root = try TemporaryDirectory.make("git-child-group")
        let held = try Self.holdingAlias(in: root, leavingTheGroup: false)
        defer { held.release() }
        let started = Date()

        let answered = Self.within { () -> Bool in
            (try? GitContext.run(arguments: held.arguments, in: root, within: ChildDeadline.git)) == nil
        }
        let elapsed = Date().timeIntervalSince(started)

        guard let failed = answered else {
            Issue.record("the call was still open \(Self.hookBudget) seconds on: a descendant holding the pipe kept it")
            return
        }
        #expect(failed, "the alias never exits by itself, so the call cannot have succeeded")
        #expect(elapsed < ChildDeadline.git + 0.5, "the call took \(elapsed) seconds")
        let pid = try #require(held.pid(), "the alias never wrote the sleep's pid")
        #expect(Self.isGone(pid), "the sleep (pid \(pid)) is still running after the call")
    }

    /// A descendant that left git's group cannot be signalled with it, and still does not hold the call: reading stops at the deadline whatever holds the pipe.
    @Test
    func aDescendantThatLeftTheGroupDoesNotHoldTheCallPastItsBound() throws {
        let root = try TemporaryDirectory.make("git-child-left-group")
        let held = try Self.holdingAlias(in: root, leavingTheGroup: true)
        defer { held.release() }
        let started = Date()

        let answered = Self.within { () -> Bool in
            (try? GitContext.run(arguments: held.arguments, in: root, within: ChildDeadline.git)) == nil
        }
        let elapsed = Date().timeIntervalSince(started)

        guard let failed = answered else {
            Issue.record("the call was still open \(Self.hookBudget) seconds on: a descendant holding the pipe kept it")
            return
        }

        #expect(failed, "the alias never exits by itself, so the call cannot have succeeded")
        #expect(elapsed < ChildDeadline.git + 0.5, "the call took \(elapsed) seconds")
    }

    /// `changedFiles` is a bulk read: a range diff whose git takes 3 seconds to open the repository's objects is still answered.
    @Test
    func theRangeDiffOfARepositoryWhoseObjectsTakeThreeSecondsToOpenIsStillRead() throws {
        let root = try TemporaryDirectory.make("git-child-bulk-range")
        try TestSources.runGit(["init", "-q"], in: root)
        try #require(ChildDeadline.gitRead(in: root) == ChildDeadline.git, "the repository's reads are widened, so a caller that dropped its bulk bound would pass")
        let toplevel = try #require(GitContext.spawnedRoot(from: root, within: ChildDeadline.gitBulk))
        try #require(toplevel.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path, "the fixture repository is not the temporary directory")
        let identity = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid"]
        try Data("struct A {}\n".utf8).write(to: root.appendingPathComponent("A.swift"))
        try TestSources.runGit(["add", "."], in: root)
        try TestSources.runGit(identity + ["commit", "-q", "-m", "one"], in: root)
        try Data("struct B {}\n".utf8).write(to: root.appendingPathComponent("B.swift"))
        try TestSources.runGit(["add", "."], in: root)
        try TestSources.runGit(identity + ["commit", "-q", "-m", "two"], in: root)
        let first = try TestSources.runGit(["rev-parse", "HEAD~1"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = try TestSources.runGit(["rev-parse", "HEAD"], in: root).trimmingCharacters(in: .whitespacesAndNewlines)
        // git blocks opening an alternates file that is a FIFO until a writer opens it; this one opens 3 seconds on.
        let alternates = root.appendingPathComponent(".git/objects/info/alternates").path
        guard mkfifo(alternates, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Self.openForWriting(alternates) }
        let writer = Thread {
            Thread.sleep(forTimeInterval: 3)
            Self.openForWriting(alternates)
        }
        writer.start()

        let answered = Self.within(Self.bulkBudget) { () -> [String]? in
            try? GitContext(repoRoot: root).changedFiles(from: first, to: second).map(\.path)
        }

        let paths = try #require(answered, "the range diff was still running \(Self.bulkBudget) seconds on")

        #expect(paths == ["B.swift"])
    }

    /// A child that has already exited when its deadline passes is not reported as timed out: the deadline ended nothing.
    @Test
    func aChildGoneBeforeItsDeadlinePassesIsNotTimedOut() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let watch = ChildDeadline.Watch(process, within: 0.05)

        watch.arm()
        usleep(300_000)

        #expect(!watch.timedOut)
    }
}

/// The places that once took an unanswered git as no repository and said so, or skipped a guard on it.
extension GitChildBoundTests {
    /// A run's inventory line over such a tree says the inventory could not be read, not that the tree is in no repository.
    @Test
    func theInventoryOfATreeGitDoesNotAnswerForIsUnreadNotRepositoryless() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered-inventory"))
        defer { fixture.release() }

        let root = fixture.root

        let answered = Self.within(Self.unansweredBudget) { () -> String in
            let check = RunInventoryCheck.check(RunTestOutcomes(), loggedAt: nil, repositoryRoot: root)
            guard case let .skipped(reason) = check else { return "expected .skipped, got \(check)" }
            return reason
        }
        fixture.release()
        let reason = try #require(answered, "the inventory check was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        #expect(reason.hasPrefix("the inventory could not be read: git did not answer within "), "\(reason)")
        #expect(!reason.contains("is not inside a git repository"), "\(reason)")
    }

    /// A document outside the root, in a tree git does not answer for, is refused naming the unanswered git, not as in no repository.
    @Test
    func aDocumentInATreeGitDoesNotAnswerForIsNotToldAsInNoRepository() async throws {
        let repository = try TestSources.makeTempRepo()
        try TestSources.write("struct Anchor {}\n", to: "Sources/App/Anchor.swift", in: repository)
        try TestSources.commitAll(in: repository, message: "seed")
        let engine = try SiftEngine(directory: repository)
        _ = try await engine.ensureFresh()
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered-digest"))
        defer { fixture.release() }
        let document = fixture.root.appendingPathComponent("Notes.md")
        try "# Notes\n\nOne line.\n".write(to: document, atomically: true, encoding: .utf8)

        let path = document.path
        let answered = Self.within(Self.unansweredBudget) { () -> String in
            do {
                return try engine.digest(target: path, options: DigestOptions())
            } catch {
                return "threw: \(error)"
            }
        }
        fixture.release()
        let answer = try #require(answered, "the digest was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        let outside = "\(document.path) is outside this root (\(CanonicalPath.of(engine.repoRoot.path))) — the file is there, but git did not answer within "

        #expect(answer.hasPrefix(outside), "\(answer)")
        #expect(answer.contains("so which repository it is in is not known"), "\(answer)")
        #expect(!answer.contains("in no repository to root at"), "\(answer)")
    }

    /// Uninstall does not run `claude mcp remove` in a project git does not answer for: which root Claude Code keys it by is not known, so it is named for removal by hand.
    @Test
    func aLocalServerInAProjectGitDoesNotAnswerForIsNotRemoved() throws {
        let fixture = try Fixture(root: TemporaryDirectory.make("git-unanswered-uninstall"))
        defer { fixture.release() }
        let project = CanonicalPath.of(fixture.root.path)
        let scratch = try TemporaryDirectory.make("git-unanswered-uninstall-config")
        let config = scratch.appendingPathComponent(".claude.json")
        let registration: [String: Any] = ["command": "npx", "args": ["--yes", "@agulhas-labs/sift", "mcp"]]
        try JSONSerialization.data(withJSONObject: ["mcpServers": [:], "projects": [project: ["mcpServers": ["swift-sure": registration]]]]).write(to: config)
        let locations = SiftUninstall.Locations(settings: scratch.appendingPathComponent("settings.json"), claudeConfig: config, rule: scratch.appendingPathComponent("swift-sure.md"), siftHome: scratch.appendingPathComponent(".swift-sure"), logs: [])

        let answered = Self.within(Self.unansweredBudget) { () -> UninstallAnswers in
            var asked = 0
            let step = UninstallServers.settle(locations, roots: []) { _ in
                asked += 1
                return .removed
            }
            return UninstallAnswers(asked: asked, failures: step.failures, notes: step.notes)
        }
        fixture.release()
        let step = try #require(answered, "the uninstall step was still waiting on git after \(Self.unansweredBudget) seconds: the call has no bound")

        #expect(step.asked == 0, "claude mcp remove ran in a project git did not answer for")
        #expect(step.failures == 1, "\(step.notes)")
        let prefix = "mcp: not removed — the local-scope server in \(project) runs npx --yes @agulhas-labs/sift mcp; git did not answer within "
        let suffix = "Until it does, `claude mcp remove swift-sure --scope local` is not run there, since it could reach another root's entry: remove projects[\"\(project)\"].mcpServers.swift-sure from \(config.path) by hand"
        #expect(step.notes.contains { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }, "\(step.notes)")
    }
}

private extension GitChildBoundTests {
    /// A git alias, as `-c` arguments, whose script leaves `sleep 30` running with git's stdout and stderr and writes its pid down — in git's process group, or in one of its own.
    ///
    /// The sleep is a grandchild of git's, behind a shell that waits for it: git passes a `SIGTERM` it takes on to the alias's own process, and the sleep must not be that process, or it would be ended without any group.
    static func holdingAlias(in root: URL, leavingTheGroup: Bool) throws -> HeldPipe {
        let pidFile = root.appendingPathComponent("sleep.pid")
        let script = root.appendingPathComponent("hold.sh")
        let jobControl = leavingTheGroup ? "set -m\n" : ""
        try Data("#!/bin/sh\n\(jobControl)sleep 30 &\necho $! > '\(pidFile.path)'\nwait\n".utf8).write(to: script)
        guard chmod(script.path, 0o755) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return HeldPipe(arguments: ["-c", "alias.hold=!\(script.path)", "hold"], pidFile: pidFile)
    }

    /// Opens `fifo` for writing without blocking and closes it again, which releases a reader blocked opening it; nothing where no reader is waiting.
    static func openForWriting(_ fifo: String) {
        let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// Whether `pid` has left the process table, given a second for its new parent to reap it.
    static func isGone(_ pid: pid_t) -> Bool {
        let limit = Date() + 1
        while Date() < limit {
            if kill(pid, 0) == -1, errno == ESRCH {
                return true
            }
            usleep(20000)
        }
        return false
    }

    /// The alias a holding test runs, and where its sleep's pid is written.
    struct HeldPipe {
        let arguments: [String]
        let pidFile: URL

        func pid() -> pid_t? {
            (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }

        /// Ends the sleep this test started, if it is still running.
        func release() {
            if let pid = pid(), pid > 1, kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    /// A repository git accepts as one, whose config includes a FIFO.
    struct Fixture {
        let root: URL
        let fifo: String

        init(root: URL) throws {
            self.root = root
            let git = root.appendingPathComponent(".git", isDirectory: true)
            for sub in ["objects", "refs"] {
                try FileManager.default.createDirectory(at: git.appendingPathComponent(sub), withIntermediateDirectories: true)
            }
            try Data("ref: refs/heads/main\n".utf8).write(to: git.appendingPathComponent("HEAD"))
            fifo = root.appendingPathComponent("config.fifo").path
            guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let config = "[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n"
            try Data(config.utf8).write(to: git.appendingPathComponent("config"))
        }

        /// Opens the FIFO's write end without blocking, which releases any git still blocked reading it, then closes it.
        func release() {
            let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 {
                close(descriptor)
            }
        }
    }

    struct BoundAnswers: Sendable {
        let discovered: Bool
        let first: String
        let second: String
    }

    struct UninstallAnswers: Sendable {
        let asked: Int
        let failures: Int
        let notes: [String]
    }

    struct Reaped: Sendable {
        let pid: Int32
        let timedOut: Bool
        let gone: Bool
    }

    final class Box<Value>: @unchecked Sendable {
        var value: Value?
    }
}
