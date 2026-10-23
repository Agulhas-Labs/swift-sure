//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers a shard's device going the moment that shard has ended, rather than at the teardown after the slowest one.
///
/// The run-level cases drive a real ``ShardRunner`` over launches that never start a process, so the order a shard ends in and the order its device is deleted in are both in the one event log — all but the one about a cancellation, whose runner names a shard the real one would not, so the run's own refusal is what it reaches. The runner-level cases pin the hook itself: every shard named but the last to finish, none named before its session is ended, and none once the run is cancelled.
@Suite(.temporaryDirectories)
struct EarlyShardDeleteTests {
    /// A shard that ends first has its device deleted while the other is still running, and the last one's device goes in the teardown — each once, and the devices line still counts both.
    @Test
    func aShardThatEndsFirstHasItsDeviceDeletedBeforeTheLastShardEnds() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let events = TestRunTests.Recorder()
        let deleted = DispatchSemaphore(value: 0)
        var fake = Self.fake(in: root)
        fake.deleting = { _ in
            deleted.signal()
            return Self.succeeded
        }
        fake.makeRunner = Self.runner(in: root, events: events) { shard in
            if shard == 1 {
                _ = deleted.wait(timeout: .now() + 5)
            }
        }

        let result = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events)).run()

        let sequence = events.taken()
        let first = try #require(Self.device(ofShard: 2, in: sequence))
        let last = try #require(Self.device(ofShard: 1, in: sequence))
        let lastEnded = try #require(sequence.firstIndex(of: "shard 1 ended on \(last)"))

        #expect(try #require(sequence.firstIndex(of: "simctl delete \(first)")) < lastEnded)
        #expect(try #require(sequence.firstIndex(of: "simctl delete \(last)")) > lastEnded)
        #expect(TestRunTests.deleted(sequence).sorted() == [first, last].sorted())
        #expect(result.answer.contains("2 simulators created, 2 deleted"))
    }

    /// A cancellation while one shard still runs reaches that shard without waiting out the other's delete, and its teardown waits for that delete rather than missing the device or deleting it again.
    @Test
    func aCancellationWhileAShardStillRunsDeletesEveryDeviceOnce() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let events = TestRunTests.Recorder()
        let holder = TestRunTests.RunHolder()
        let calls = Calls()
        let deleteBegan = DispatchSemaphore(value: 0)
        let shardsCancelled = DispatchSemaphore(value: 0)
        var fake = Self.fake(in: root)
        fake.deleting = { _ in
            guard calls.next() == 0 else {
                return Self.succeeded
            }
            // The early delete is still under way when the cancellation arrives, and answers only once it has reached the shards.
            deleteBegan.signal()
            let reached = shardsCancelled.wait(timeout: .now() + 5) == .success
            events.append(reached ? "early delete answered after the shards were cancelled" : "early delete gave up waiting for the cancellation")
            return Self.succeeded
        }
        fake.makeRunner = Self.runner(in: root, events: events, cancelled: { shardsCancelled.signal() }, before: { shard in
            guard shard == 1 else {
                return
            }
            _ = deleteBegan.wait(timeout: .now() + 5)
            holder.cancelFromAnotherThread(exitCode: 130)
        })
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        let sequence = events.taken()
        let first = try #require(Self.device(ofShard: 2, in: sequence))
        let last = try #require(Self.device(ofShard: 1, in: sequence))

        #expect(result.exitCode == 130)
        #expect(try #require(sequence.firstIndex(of: "simctl delete \(first)")) < #require(sequence.firstIndex(of: "shards cancelled")))
        #expect(sequence.contains("early delete answered after the shards were cancelled"))
        #expect(TestRunTests.deleted(sequence).sorted() == [first, last].sorted())
        #expect(result.answer.contains("2 simulators created, 2 deleted"))
        #expect(sequence.filter { $0 == "watcher released" }.count == 1)
    }

    /// A shard that ends after a cancellation was recorded, while the cancellation is still ending the others, leaves its device to the teardown: its `xcodebuild` may not be gone yet, so every device is deleted by the teardown after the sessions end, each once.
    ///
    /// The runner here names that shard regardless, as one without its own check would, so what is pinned is the run's refusal rather than the runner's.
    @Test
    func aShardEndingAfterACancellationLeavesItsDeviceToTheTeardown() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let events = TestRunTests.Recorder()
        let holder = TestRunTests.RunHolder()
        let teardownThread = ThreadHolder()
        let offTeardown = Named()
        let cancelReached = DispatchSemaphore(value: 0)
        let shardNamed = DispatchSemaphore(value: 0)
        let cancelFinished = DispatchSemaphore(value: 0)
        var fake = Self.fake(in: root)
        fake.deleting = { _ in
            if !teardownThread.isCurrent {
                offTeardown.append(1)
            }
            return Self.succeeded
        }
        fake.makeRunner = { _ in
            TestRunEnvironment.Shards(
                runEnding: { assignments, ended in
                    for assignment in assignments {
                        events.append("shard \(assignment.index) ended on \(Self.device(in: assignment.argv))")
                    }
                    Thread.detachNewThread {
                        holder.take()?.cancel(exitCode: 130)
                        cancelFinished.signal()
                    }
                    // Shard 2 ends while the cancellation is still ending the sessions, before its teardown.
                    _ = cancelReached.wait(timeout: .now() + 5)
                    ended(2)
                    shardNamed.signal()
                    _ = cancelFinished.wait(timeout: .now() + 5)
                    return assignments.map { _ in Self.outcome }
                },
                cancel: {
                    // The cancellation's teardown runs on this thread once this returns.
                    teardownThread.put(Thread.current)
                    cancelReached.signal()
                    _ = shardNamed.wait(timeout: .now() + 5)
                    events.append("shards cancelled")
                }
            )
        }
        let run = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events))
        holder.put(run)

        let result = run.run()

        let sequence = events.taken()
        let first = try #require(Self.device(ofShard: 2, in: sequence))
        let last = try #require(Self.device(ofShard: 1, in: sequence))
        let cancelled = try #require(sequence.firstIndex(of: "shards cancelled"))

        #expect(result.exitCode == 130)
        #expect(offTeardown.taken().isEmpty)
        #expect(try #require(sequence.firstIndex(of: "simctl delete \(first)")) > cancelled)
        #expect(TestRunTests.deleted(sequence).sorted() == [first, last].sorted())
        #expect(result.answer.contains("2 simulators created, 2 deleted"))
    }

    /// An early delete that fails leaves the device in the record, so the teardown tries it again — and the devices line counts it once, as gone.
    @Test
    func aFailedEarlyDeleteIsRetriedByTheTeardownAndCountedOnce() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let events = TestRunTests.Recorder()
        let calls = Calls()
        let attempted = DispatchSemaphore(value: 0)
        var fake = Self.fake(in: root)
        fake.deleting = { _ in
            guard calls.next() == 0 else {
                return Self.succeeded
            }
            attempted.signal()
            return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Unable to delete a device in the Booted state\n")
        }
        fake.makeRunner = Self.runner(in: root, events: events) { shard in
            if shard == 1 {
                _ = attempted.wait(timeout: .now() + 5)
            }
        }

        let result = TestRun(request: TestRunTests.request(in: root), environment: fake.environment(events)).run()

        let sequence = events.taken()
        let first = try #require(Self.device(ofShard: 2, in: sequence))
        let last = try #require(Self.device(ofShard: 1, in: sequence))

        #expect(try #require(sequence.firstIndex(of: "simctl delete \(first)")) < #require(sequence.firstIndex(of: "shard 1 ended on \(last)")))
        #expect(TestRunTests.deleted(sequence).sorted() == [first, first, last].sorted())
        #expect(result.answer.contains("2 simulators created, 2 deleted"))
        // No failure is left to report, so no command to delete one by hand is printed.
        #expect(!result.answer.contains("simctl delete"))
    }

    /// The runner names every shard but the last to finish, in the order they finished — and has named them all by the time it returns.
    @Test
    func theRunnerNamesEveryShardButTheLastToFinish() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let named = Named()
        let signals = [0, 1, 2].map { _ in DispatchSemaphore(value: 0) }
        // Shard 2 finishes first, then shard 0 once 2 was named, then shard 1 once 0 was.
        let waitsFor = [0: 2, 1: 0]
        let runner = ShardRunner(
            workingDirectory: root,
            repositoryRoot: nil,
            children: SetAsideChildren(),
            launch: { assignment, _, _ in
                if let other = waitsFor[assignment.index] {
                    _ = signals[other].wait(timeout: .now() + 10)
                }
                return Self.outcome
            }
        )

        let outcomes = runner.run([Self.assignment(0), Self.assignment(1), Self.assignment(2)]) { index in
            named.append(index)
            signals[index].signal()
        }

        #expect(outcomes.count == 3)
        #expect(named.taken() == [2, 0])
    }

    /// A shard is named only once its session has been ended: a process its leader left running is gone by then, because an `xcodebuild` still driving a device that is being deleted wedges CoreSimulator.
    @Test
    func theRunnerNamesAShardOnlyOnceItsSessionHasEnded() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let children = SetAsideChildren()
        defer { children.endAll() }
        let leader = Named()
        let left = Named()
        let firstNamed = DispatchSemaphore(value: 0)
        let runner = ShardRunner(
            workingDirectory: root,
            repositoryRoot: nil,
            children: children,
            launch: { assignment, launched, _ in
                guard assignment.index == 0 else {
                    _ = firstNamed.wait(timeout: .now() + 10)
                    return Self.outcome
                }
                let null = open("/dev/null", O_RDWR)
                defer { close(null) }
                // The leader exits at once and leaves a process behind in its session, as an `xcodebuild` can.
                let pid = try children.spawn(
                    "/bin/sh",
                    ["-c", "sleep 30 &"],
                    in: root,
                    environment: [:],
                    streams: SetAsideChildren.Streams(input: null, output: null, error: null)
                )
                leader.append(Int(pid))
                launched(pid)
                _ = SetAsideChildren.exitCode(waitingFor: pid)
                return Self.outcome
            }
        )

        _ = runner.run([Self.assignment(0), Self.assignment(1)]) { _ in
            let session = SetAsideChildren.Session(pid: pid_t(leader.taken().first ?? 0), started: 0)
            left.append(SetAsideChildren.members(of: session).count)
            firstNamed.signal()
        }

        #expect(leader.taken().count == 1)
        #expect(left.taken() == [0])
    }

    /// No shard is named once the run is cancelled: the cancellation ends the sessions one at a time, so a shard's supervisor can return while its `xcodebuild` is still being ended.
    @Test
    func theRunnerNamesNoShardThatEndsAfterACancellation() throws {
        let root = try TemporaryDirectory.make("early-shard-delete")
        let named = Named()
        let started = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        let runner = ShardRunner(
            workingDirectory: root,
            repositoryRoot: nil,
            children: SetAsideChildren(),
            launch: { _, _, _ in
                started.signal()
                _ = released.wait(timeout: .now() + 10)
                return Self.outcome
            },
            patience: 1
        )
        Thread.detachNewThread {
            _ = runner.run([Self.assignment(0), Self.assignment(1)]) { index in
                named.append(index)
            }
            returned.signal()
        }
        _ = started.wait(timeout: .now() + 10)
        _ = started.wait(timeout: .now() + 10)

        runner.cancel()
        released.signal()
        released.signal()

        #expect(returned.wait(timeout: .now() + 10) == .success)
        #expect(named.taken().isEmpty)
    }
}

private extension EarlyShardDeleteTests {
    static var succeeded: Subprocess.Output {
        Subprocess.Output(succeeded: true, standardOutput: "")
    }

    static var outcome: ShardOutcome {
        ShardOutcome(outcomes: RunTestOutcomes(), exitCode: 0, wallSeconds: 1, logPath: "/dev/null")
    }

    static func assignment(_ index: Int) -> ShardRunner.Assignment {
        ShardRunner.Assignment(index: index, argv: ["/usr/bin/true"], bound: 60)
    }

    /// A run of two tests on two devices, so the plan keeps both shards, which it numbers 1 and 2: shard 1 is held back, so shard 2 ends first.
    static func fake(in root: URL) -> TestRunTests.Fake {
        var fake = TestRunTests.Fake(root: root)
        fake.tests = ["DemoUnitTests/CalculatorTests/t1()", "DemoUnitTests/CalculatorTests/t2()"]
        return fake
    }

    /// A real runner over launches that start nothing: each shard does `before` with its index, then records that it ended and on which device.
    static func runner(
        in root: URL,
        events: TestRunTests.Recorder,
        cancelled: @escaping @Sendable () -> Void = {},
        before: @escaping @Sendable (Int) -> Void
    ) -> @Sendable (SetAsideChildren) -> TestRunEnvironment.Shards {
        { children in
            let runner = ShardRunner(
                workingDirectory: root,
                repositoryRoot: nil,
                children: children,
                launch: { assignment, _, _ in
                    before(assignment.index)
                    events.append("shard \(assignment.index) ended on \(device(in: assignment.argv))")
                    return outcome
                },
                patience: 1
            )
            return TestRunEnvironment.Shards(
                runEnding: { runner.run($0, ended: $1) },
                cancel: {
                    runner.cancel()
                    events.append("shards cancelled")
                    cancelled()
                }
            )
        }
    }

    /// The device a shard's argv names.
    static func device(in argv: [String]) -> String {
        let prefix = "platform=iOS Simulator,id="
        return argv.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } ?? "no device"
    }

    /// The device a shard recorded ending on, or `nil` where it never ended.
    static func device(ofShard index: Int, in events: [String]) -> String? {
        let prefix = "shard \(index) ended on "
        return events.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// How many times a seam has been called, counted across the threads that call it.
    final class Calls: @unchecked Sendable {
        private let gate = NSLock()
        private var count = 0

        /// This call's position, from zero.
        func next() -> Int {
            gate.withLock {
                defer { count += 1 }
                return count
            }
        }
    }

    /// The thread a teardown runs on, set from that thread and asked about from others.
    final class ThreadHolder: @unchecked Sendable {
        private let gate = NSLock()
        private var thread: Thread?

        func put(_ thread: Thread) {
            gate.withLock { self.thread = thread }
        }

        /// Whether the calling thread is the one recorded.
        var isCurrent: Bool {
            gate.withLock { thread.map { $0 === Thread.current } ?? false }
        }
    }

    /// Numbers appended from several threads, in the order they arrived.
    final class Named: @unchecked Sendable {
        private let gate = NSLock()
        private var values: [Int] = []

        func append(_ value: Int) {
            gate.withLock { values.append(value) }
        }

        func taken() -> [Int] {
            gate.withLock { values }
        }
    }
}
