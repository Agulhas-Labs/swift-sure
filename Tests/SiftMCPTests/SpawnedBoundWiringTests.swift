//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The built binary's git reads take their bound from `SWIFT_SURE_TEST_GIT_LIMIT`: pinned in the direction that load cannot flip.
///
/// The fixture is a repository whose `.git/config` names a FIFO as an include, fed by the test only 3 seconds after the first git call opens it, and at once for every later open: the first read blocks that long from its own start, past the 2-second production bound and far inside the 60 the binary is given. A binary that ignored the variable would report git as not answering; one that honours it waits git out and answers. Load can only make git slower, which stays well under 60.
@Suite(.temporaryDirectories)
struct SpawnedBoundWiringTests {
    @Test
    func aGitSlowerThanTheDefaultBoundIsWaitedOutUnderTheGivenLimit() throws {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle, at \(BuiltExecutable.expected.path)")
        let scratch = try TemporaryDirectory.make("spawned-git-limit")
        let repo = scratch.appendingPathComponent("repo", isDirectory: true)
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        let fifo = repo.appendingPathComponent("config.fifo").path
        try Self.makeRepository(at: repo, fifo: fifo)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("struct Gizmo {}\n".utf8).write(to: repo.appendingPathComponent("Gizmo.swift"))
        let feeder = Feeder(fifo: fifo, after: 3)
        feeder.start()
        defer { feeder.stop() }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["where", "Gizmo"]
        process.currentDirectoryURL = repo
        var environment = ProcessEnvironment.withoutGit()
        environment["CFFIXED_USER_HOME"] = home.path
        environment["HOME"] = home.path
        environment["SWIFT_SURE_USAGE_LOG"] = home.appendingPathComponent("usage.jsonl").path
        environment["SWIFT_SURE_HOME"] = home.appendingPathComponent("sift-home").path
        environment["SWIFT_SURE_ADVICE_DIR"] = home.appendingPathComponent("advice").path
        environment["CLAUDE_CODE_SESSION_ID"] = nil
        environment["SWIFT_SURE_TEST_GIT_LIMIT"] = "60"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let ender = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: ender)
        defer { ender.cancel() }
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(bytes: printed, encoding: .utf8) ?? ""

        #expect(!text.contains("did not answer"), "the binary cut git off at its production bound: \(text)")
        #expect(text.contains("Gizmo.swift:1"), "\(text)")
        #expect(process.terminationStatus == 0, "\(text)")
    }

    private static func makeRepository(at root: URL, fifo: String) throws {
        let dotGit = root.appendingPathComponent(".git", isDirectory: true)
        for sub in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: dotGit.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/main\n".utf8).write(to: dotGit.appendingPathComponent("HEAD"))
        guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let config = "[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n"
        try Data(config.utf8).write(to: dotGit.appendingPathComponent("config"))
    }
}

extension SpawnedBoundWiringTests {
    /// Feeds a valid config into the FIFO to each reader that opens it: the first `after` seconds after it opens, so a slow start cannot eat the wait, and every later one at once.
    private final class Feeder: @unchecked Sendable {
        private let fifo: String
        private let after: TimeInterval
        private let lock = NSLock()
        private var stopped = false
        private let finished = DispatchSemaphore(value: 0)

        init(fifo: String, after: TimeInterval) {
            self.fifo = fifo
            self.after = after
        }

        private var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func start() {
            Thread {
                var first = true
                while !self.isStopped {
                    // Blocks until a reader opens the FIFO: a git, or `stop`.
                    let descriptor = open(self.fifo, O_WRONLY)
                    guard descriptor >= 0 else { break }
                    let deadline = Date().addingTimeInterval(first ? self.after : 0)
                    first = false
                    while Date() < deadline, !self.isStopped {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if self.isStopped {
                        close(descriptor)
                        break
                    }
                    _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
                    let body = Array("[user]\n\tname = fixture\n".utf8)
                    _ = write(descriptor, body, body.count)
                    close(descriptor)
                }
                self.finished.signal()
            }.start()
        }

        /// Ends the feeding: a reader opened and closed without blocking releases a writer waiting in `open`.
        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
            for _ in 0 ..< 50 {
                let descriptor = open(fifo, O_RDONLY | O_NONBLOCK)
                if descriptor >= 0 {
                    close(descriptor)
                }
                if finished.wait(timeout: .now() + 0.1) == .success {
                    break
                }
            }
            unlink(fifo)
        }
    }
}
