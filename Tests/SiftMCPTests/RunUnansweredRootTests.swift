//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// A `swift-sure run` in a tree whose git does not answer is refused, naming that, rather than run without the set-aside guard.
///
/// The tree is a repository whose `.git/config` includes a FIFO nobody writes, so `git rev-parse` blocks opening it until its bound ends it.
@Suite(.temporaryDirectories)
struct RunUnansweredRootTests {
    /// Whether work is set aside out of such a tree is not known, so the run refuses and the command never starts.
    @Test
    func aRunInATreeWhoseRootGoesUnansweredRefusesAndRunsNothing() throws {
        let root = try TemporaryDirectory.make("run-unanswered-root")
        let fifo = try Self.blockingRepository(at: root)
        defer { Self.release(fifo) }
        let marker = root.appendingPathComponent("ran")

        let (status, output) = try Self.sift(["run", "--", "/usr/bin/touch", marker.path], in: root)

        #expect(status == 1, "\(output)")
        #expect(output.contains("swift-sure run: refusing to start — git did not answer within "), "\(output)")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the command ran in a tree git did not answer for")
    }

    /// A command that builds such a tree through `-C`, run from a directory in no repository, is refused the same way: the checkout it builds is not known.
    @Test
    func aRunWhoseBuiltCheckoutGoesUnansweredRefusesAndRunsNothing() throws {
        let built = try TemporaryDirectory.make("run-unanswered-built")
        let fifo = try Self.blockingRepository(at: built)
        defer { Self.release(fifo) }
        let launched = try TemporaryDirectory.make("run-unanswered-launched")
        let marker = launched.appendingPathComponent("ran")

        let (status, output) = try Self.sift(["run", "--", "/bin/sh", "-c", "/usr/bin/touch '\(marker.path)'", "-C", built.path], in: launched)

        #expect(status == 1, "\(output)")
        #expect(output.contains("swift-sure run: refusing to start — git did not answer within "), "\(output)")
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the command ran over a checkout git did not answer for")
    }

    /// `--without` in such a tree is a refusal, exit 2 with nothing taken out, never the exit 1 that says the runs happened and proved nothing.
    @Test
    func aRunWithoutInATreeWhoseRootGoesUnansweredIsRefused() throws {
        let root = try TemporaryDirectory.make("run-unanswered-without")
        let fifo = try Self.blockingRepository(at: root)
        defer { Self.release(fifo) }

        let (status, output) = try Self.sift(["run", "--without", "Sources/", "--", "swift", "test", "--filter", "WidgetTests"], in: root)

        #expect(status == 2, "\(output)")
        #expect(output.contains("swift-sure run --without: git did not answer within "), "\(output)")
    }

    /// `--proved` in such a tree cannot put its question: exit 2 naming the timeout, which the pre-push hook runs the suite on, never the 1 that refuses a push as unproved.
    @Test
    func aProvedInATreeWhoseRootGoesUnansweredCannotBePut() throws {
        let root = try TemporaryDirectory.make("run-unanswered-proved")
        let fifo = try Self.blockingRepository(at: root)
        defer { Self.release(fifo) }

        let (status, output) = try Self.sift(["run", "--proved", "--", "swift", "test"], in: root)

        #expect(status == 2, "\(output)")
        #expect(output.contains("the question could not be put: git did not answer within "), "\(output)")
    }

    /// `--restore` in such a tree is a refusal too, exit 2, in its own prefix.
    @Test
    func aRestoreInATreeWhoseRootGoesUnansweredIsRefused() throws {
        let root = try TemporaryDirectory.make("run-unanswered-restore")
        let fifo = try Self.blockingRepository(at: root)
        defer { Self.release(fifo) }

        let (status, output) = try Self.sift(["run", "--restore"], in: root)

        #expect(status == 2, "\(output)")
        #expect(output.hasPrefix("swift-sure run --restore: git did not answer within "), "\(output)")
    }
}

private extension RunUnansweredRootTests {
    /// Makes `root` a repository git accepts as one, whose config includes a FIFO, and returns the FIFO's path.
    static func blockingRepository(at root: URL) throws -> String {
        let dotGit = root.appendingPathComponent(".git", isDirectory: true)
        for sub in ["objects", "refs"] {
            try FileManager.default.createDirectory(at: dotGit.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/main\n".utf8).write(to: dotGit.appendingPathComponent("HEAD"))
        let fifo = root.appendingPathComponent("config.fifo").path
        guard mkfifo(fifo, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try Data("[core]\n\trepositoryformatversion = 0\n[include]\n\tpath = \(fifo)\n".utf8).write(to: dotGit.appendingPathComponent("config"))
        return fifo
    }

    /// Opens the FIFO's write end without blocking, which releases any git still blocked reading it, then closes it.
    static func release(_ fifo: String) {
        let descriptor = open(fifo, O_WRONLY | O_NONBLOCK)
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// The built `swift-sure` run in `directory`, with no git variables, a home of its own and the ledger left on (the switch unset, which `--proved` needs to reach its question), and what it printed on both streams.
    static func sift(_ arguments: [String], in directory: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> (status: Int32, output: String) {
        let binary = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle, at \(BuiltExecutable.expected.path)", sourceLocation: sourceLocation)
        let home = try TemporaryDirectory.make("run-unanswered-home")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessEnvironment.withoutGit()
        environment[RunLedger.switchName] = nil
        environment["SWIFT_SURE_HOME"] = home.path
        environment["CLAUDE_CODE_SESSION_ID"] = nil
        process.environment = environment
        let sink = Pipe()
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        let output = sink.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
    }
}
