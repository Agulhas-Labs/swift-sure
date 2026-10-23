//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// ``DeadlineChild`` itself: an attempt it read as inconclusive is not forgotten once a later one is ready.
@Suite(.temporaryDirectories)
struct DeadlineChildTests {
    /// A first attempt that returns with its child still starting, never stopped, leaves that child to write its pid later; the attempts end on a ready second one, and the first child is still found running.
    ///
    /// Its bounded waits alone add up to 42 s (10 s for the pid, 10 s to reap, 2 s of grace, 20 s for the clear-up), beside launches a loaded host slows: the two-minute limit of the other `ready` callers.
    @Test(.timeLimit(.minutes(2))) func anEarlierAttemptsChildLeftRunningIsFound() async throws {
        let children = Children()
        defer { children.stopAll() }

        try await withKnownIssue {
            _ = try await DeadlineChild.ready { file in
                if children.launched.isEmpty {
                    try children.launch("sleep 0.5; " + DeadlineChild.prelude(writingPidTo: file))
                    return
                }
                let ready = try children.launch(DeadlineChild.prelude(writingPidTo: file))
                let until = Date(timeIntervalSinceNow: 10)
                while DeadlineChild.pid(in: file) == nil, Date() < until {
                    try await Task.sleep(for: .milliseconds(20))
                }
                await children.stop(ready)
            }
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("is still running or unreaped") }
        }
    }

    /// A stub child's output and errors go to the null device, never to the stream the test runner reads.
    @Test(.timeLimit(.minutes(1))) func aStubChildWritesToTheNullDevice() async throws {
        let children = Children()
        defer { children.stopAll() }
        let file = try TemporaryDirectory.make("null-device").appendingPathComponent("streams")

        try children.launch(
            "if [ /dev/fd/1 -ef /dev/null ] && [ /dev/fd/2 -ef /dev/null ]; then s=null; else s=inherited; fi; "
                + "echo $s > '\(file.path).part' && mv '\(file.path).part' '\(file.path)'; exec sleep 100000"
        )
        let until = Date(timeIntervalSinceNow: 20)
        while !FileManager.default.fileExists(atPath: file.path), Date() < until {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(try String(contentsOf: file, encoding: .utf8) == "null\n")
    }
}

extension DeadlineChildTests {
    /// The stub children one test launched, each stopped and reaped when the test ends.
    ///
    /// Exit is observed on the termination handler and waited for with a bound, never with `waitUntilExit`: that sleeps in a run loop on the calling thread, and on a cooperative-pool thread it has hung a filtered run for tens of minutes.
    final class Children: @unchecked Sendable {
        /// How long a stopped child is waited for before the test records a failure instead of waiting on.
        static let reapLimit: TimeInterval = 10

        private let lock = NSLock()
        private var exits: [pid_t: DispatchSemaphore] = [:]
        private var processes: [Process] = []

        var launched: [Process] {
            lock.withLock { processes }
        }

        /// Launches `script` under `/bin/sh` as a child of this process, writing to the null device: a child left running by a crashed test process would otherwise hold the runner's output open, and `swift test` waits on it without end.
        @discardableResult
        func launch(_ script: String) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            try process.run()
            lock.withLock {
                processes.append(process)
                exits[process.processIdentifier] = exited
            }
            return process
        }

        /// Kills `process` and waits, off the cooperative pool and for at most ``reapLimit``, for its exit; records an issue where it did not exit.
        func stop(_ process: Process, sourceLocation: SourceLocation = #_sourceLocation) async {
            let exited = lock.withLock { exits[process.processIdentifier] }
            kill(process.processIdentifier, SIGKILL)
            guard let exited else { return }
            let reaped = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let reaped = exited.wait(timeout: .now() + Self.reapLimit) == .success
                    if reaped {
                        exited.signal()
                    }
                    continuation.resume(returning: reaped)
                }
            }
            if !reaped {
                Issue.record("the killed child \(process.processIdentifier) did not exit within \(Self.reapLimit) s", sourceLocation: sourceLocation)
            }
        }

        /// Kills every child still running, then blocks the calling thread up to `reapLimit` for each to exit, one after another.
        func stopAll(sourceLocation: SourceLocation = #_sourceLocation) {
            for process in launched where process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                let exited = lock.withLock { exits[process.processIdentifier] }
                if exited?.wait(timeout: .now() + Self.reapLimit) == .timedOut {
                    Issue.record("the killed child \(process.processIdentifier) did not exit within \(Self.reapLimit) s", sourceLocation: sourceLocation)
                }
            }
        }
    }
}
