//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the async open: a caller waiting on a store open suspends, so it holds none of the cooperative pool's threads.
struct BudgetedOpenAsyncTests {
    /// Blocking waits are unavailable inside an async function, so these live outside it.
    private static func block(on gate: DispatchSemaphore, counting started: Counter) {
        started.increment()
        gate.wait()
    }

    private static func watch(_ finished: DispatchSemaphore, window: TimeInterval, then release: @escaping @Sendable () -> Void) -> Thread {
        // A thread, not `Task.sleep`, so a failure ends rather than hangs whatever the executor is doing.
        Thread {
            if finished.wait(timeout: .now() + window) == .timedOut {
                release()
            }
        }
    }

    private static func waitFor(_ counter: Counter, reaching target: Int, within window: TimeInterval = 5) async {
        // A thread polls and resumes the caller, so the wait needs no timer and no thread of the pool.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Thread {
                let deadline = Date().addingTimeInterval(window)
                while counter.value < target, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                continuation.resume()
            }.start()
        }
    }

    /// Runs several async opens on an executor of one thread: a caller that blocked there, instead of suspending, would starve the trivial task made on it.
    @available(macOS 15, *)
    private static func runPin(saturatingGlobalPool: Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        let opens = 4
        let executor = SingleThreadExecutor()
        defer { executor.shutDown() }
        let gate = DispatchSemaphore(value: 0)
        let started = Counter()
        let finished = DispatchSemaphore(value: 0)
        let timedOut = Flag()
        let release: @Sendable () -> Void = {
            for _ in 0 ..< opens {
                gate.signal()
            }
        }

        let blockerGate = DispatchSemaphore(value: 0)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let blockersStarted = Counter()
        let (value, results) = await withTaskExecutorPreference(executor) { () async -> (Int, [Bool]) in
            // Parked inside the preference: the test's own continuations must not need the pool being saturated.
            if saturatingGlobalPool {
                for _ in 0 ..< 2 * cores {
                    Task.detached { Self.block(on: blockerGate, counting: blockersStarted) }
                }
                // A bounded wait: another test can hold a pool thread, so the count may never reach the width.
                await waitFor(blockersStarted, reaching: cores, within: 1)
            }
            let waiting = Task(executorPreference: executor) {
                await withTaskGroup(of: Bool.self) { group in
                    for index in 0 ..< opens {
                        group.addTask(executorPreference: executor) {
                            let key = BudgetedOpen<Opened>.Key(path: "/store\(index)", anchor: Date(timeIntervalSince1970: 1))
                            let outcome = await BudgetedOpen<Opened>().open(key: key, budget: 30) {
                                started.increment()
                                gate.wait()
                                return Opened()
                            }
                            if case .opened = outcome {
                                return true
                            }
                            return false
                        }
                    }
                    var results: [Bool] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }
            }
            // Started before the wait on the opens: a caller that blocks the executor never reaches the count, and the watchdog is what ends it.
            let watchdog = watch(finished, window: 5) {
                timedOut.raise()
                release()
            }
            watchdog.start()
            await waitFor(started, reaching: opens)
            let value = await Task(executorPreference: executor) { 1 }.value
            finished.signal()
            release()
            if saturatingGlobalPool {
                for _ in 0 ..< 2 * cores {
                    blockerGate.signal()
                }
            }
            return await (value, waiting.value)
        }
        #expect(value == 1, sourceLocation: sourceLocation)
        #expect(!timedOut.isRaised, "an unrelated task waited for the opens: the executor was held", sourceLocation: sourceLocation)
        #expect(results.count == opens, sourceLocation: sourceLocation)
        #expect(!results.contains(false), sourceLocation: sourceLocation)
    }

    /// The property this exists for: a waiting caller holds no thread of the executor it was called on.
    ///
    /// With opens waiting, a task on the same one-thread executor still runs. The executor is the test's own, so the rest of the process cannot fail it.
    @Test
    @available(macOS 15, *)
    func aWaitingCallerHoldsNoCooperativeThread() async {
        await Self.runPin(saturatingGlobalPool: false)
    }

    /// The same pin with the global pool parked on blockers: it holds whatever the rest of the process does.
    @Test
    @available(macOS 15, *)
    func theAsyncOpenPinHoldsWithTheGlobalPoolSaturated() async {
        await Self.runPin(saturatingGlobalPool: true)
    }
}

extension BudgetedOpenAsyncTests {
    private final class Opened: @unchecked Sendable {}

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() {
            lock.withLock { count += 1 }
        }

        var value: Int {
            lock.withLock { count }
        }
    }

    /// A serial executor on one dedicated thread, drained in order.
    @available(macOS 15, *)
    private final class SingleThreadExecutor: TaskExecutor, @unchecked Sendable {
        private let condition = NSCondition()
        private var jobs: [UnownedJob] = []
        private var stopped = false

        init() {
            let thread = Thread { [unowned self] in drain() }
            thread.name = "BudgetedOpenAsyncTests.executor"
            thread.start()
        }

        func enqueue(_ job: consuming ExecutorJob) {
            let unowned = UnownedJob(job)
            condition.withLock {
                jobs.append(unowned)
                condition.signal()
            }
        }

        func shutDown() {
            condition.withLock {
                stopped = true
                condition.signal()
            }
        }

        private func drain() {
            while true {
                let next: UnownedJob? = condition.withLock {
                    while jobs.isEmpty, !stopped {
                        condition.wait()
                    }
                    return jobs.isEmpty ? nil : jobs.removeFirst()
                }
                guard let next else { return }
                next.runSynchronously(on: asUnownedTaskExecutor())
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        func raise() {
            lock.withLock { raised = true }
        }

        var isRaised: Bool {
            lock.withLock { raised }
        }
    }
}
