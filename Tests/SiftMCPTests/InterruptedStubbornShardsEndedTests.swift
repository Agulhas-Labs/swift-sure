//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
import Testing

/// The built `swift-sure test --shards 2` whose tests ignore `SIGTERM`, signalled at its pid and at its process group: once it has exited, nothing is left running in either shard's session.
///
/// A test process that outlives the `SIGTERM` is the one only the `SIGKILL` after the grace ends, so a run that answers before that grace is out leaves it running for good.
@Suite(.temporaryDirectories)
struct InterruptedStubbornShardsEndedTests {
    /// How long a wait for an outcome goes on before the outcome counts as never coming.
    private static let patience: TimeInterval = 480

    /// How long after SwiftSure has exited a shard's process may still be found before it counts as left running.
    private static let afterExit: TimeInterval = 5

    @Test(.timeLimit(.minutes(10)))
    func aRunSignalledAtItsPidLeavesNoShardProcessRunning() async throws {
        try await Self.signalled(expecting: 128 + SIGTERM) { sift in
            kill(sift, SIGTERM)
        }
    }

    @Test(.timeLimit(.minutes(10)))
    func aRunSignalledAtItsGroupLeavesNoShardProcessRunning() async throws {
        try await Self.signalled(expecting: 128 + SIGINT) { sift in
            killpg(sift, SIGINT)
        }
    }
}

private extension InterruptedStubbornShardsEndedTests {
    /// A package of two test classes, each of which ignores `SIGTERM`, records its process id and session id in the markers directory, and then waits to be ended.
    static func package(recordingIn markers: URL) throws -> URL {
        let root = try TemporaryDirectory.make("stubborn-shards")
        let manifest = "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"Gizmo\"), .testTarget(name: \"GizmoTests\", dependencies: [\"Gizmo\"])])\n"
        var files = ["Package.swift": manifest, "Sources/Gizmo/Gizmo.swift": "public let gizmo = 1\n"]
        for name in ["Alpha", "Beta"] {
            let marker = markers.appendingPathComponent(name).path
            files["Tests/GizmoTests/\(name)Tests.swift"] = "import Foundation\nimport XCTest\n\nfinal class \(name)Tests: XCTestCase {\n    func test() {\n        signal(SIGTERM, SIG_IGN)\n        FileManager.default.createFile(atPath: \"\(marker)\", contents: Data(\"\\(getpid()) \\(getsid(0))\".utf8))\n        Thread.sleep(forTimeInterval: 300)\n    }\n}\n"
        }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    /// The test process and the session a test wrote to the file, once it has.
    static func recorded(in file: URL) -> (process: pid_t, session: pid_t)? {
        let fields = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: " ").compactMap { pid_t($0) }
        return fields.count == 2 ? (fields[0], fields[1]) : nil
    }

    /// Every live process in the sessions the shards' tests ran in.
    static func left(in sessions: [pid_t]) -> [pid_t] {
        sessions.flatMap { SetAsideChildren.members(of: SetAsideChildren.Session(pid: $0, started: 0)) }
    }

    /// Runs the built SwiftSure on the package until both shards' tests are running, hands its pid to the signal it is given, and checks that it exits with the status expected and leaves nothing running in either shard's session.
    static func signalled(
        expecting status: Int32,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ send: @escaping @Sendable (pid_t) -> Void
    ) async throws {
        let sift = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle, at \(BuiltExecutable.expected.path)", sourceLocation: sourceLocation)
        let scratch = try TemporaryDirectory.make("stubborn-shards-scratch")
        let markers = scratch.appendingPathComponent("markers", isDirectory: true)
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        let config = scratch.appendingPathComponent("config", isDirectory: true)
        for directory in [markers, home, config] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let package = try Self.package(recordingIn: markers)
        defer {
            try? FileManager.default.removeItem(at: package)
            try? FileManager.default.removeItem(at: scratch)
        }
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["CLAUDE_CONFIG_DIR"] = config.path
        environment["SWIFT_SURE_HOME"] = home.path
        environment["SWIFT_SURE_ADVICE_DIR"] = scratch.appendingPathComponent("advice").path
        environment["SWIFT_SURE_USAGE_LOG"] = scratch.appendingPathComponent("usage.jsonl").path
        // The shard logs live in a repository's own state directory, so the package is made one.
        let initialise = Process()
        initialise.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initialise.arguments = ["init", "--quiet"]
        initialise.currentDirectoryURL = package
        initialise.environment = environment
        try initialise.run()
        initialise.waitUntilExit()
        try #require(initialise.terminationStatus == 0, sourceLocation: sourceLocation)
        let output = scratch.appendingPathComponent("answer.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let sink = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = sift
        process.arguments = ["test", "--shards", "2"]
        process.currentDirectoryURL = package
        process.environment = environment
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        let markerFiles = ["Alpha", "Beta"].map { markers.appendingPathComponent($0) }
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            let sessions = markerFiles.compactMap { Self.recorded(in: $0)?.session }
            for member in Self.left(in: sessions) {
                kill(member, SIGKILL)
            }
        }
        // A group signal has to reach SwiftSure's group alone, never the one this suite runs in.
        try #require(getpgid(process.processIdentifier) == process.processIdentifier, sourceLocation: sourceLocation)
        // Until both shards' tests are running, or the run has ended without starting them; polled off the concurrency pool, which a loaded suite can hold.
        await InPlaceAnswerTests.onItsOwnThread {
            let started = Date()
            while markerFiles.contains(where: { Self.recorded(in: $0) == nil }), process.isRunning, Date().timeIntervalSince(started) < Self.patience {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let shards = try markerFiles.map {
            try #require(Self.recorded(in: $0), "a shard's test never started: \((try? String(contentsOf: output, encoding: .utf8)) ?? "")", sourceLocation: sourceLocation)
        }

        send(process.processIdentifier)
        await InPlaceAnswerTests.onItsOwnThread { process.waitUntilExit() }
        let answer = (try? String(contentsOf: output, encoding: .utf8)) ?? ""

        #expect(process.terminationReason == .exit && process.terminationStatus == status, "ended \(process.terminationReason.rawValue) with \(process.terminationStatus): \(answer)", sourceLocation: sourceLocation)
        #expect(answer.contains("the run was interrupted, so its shards were ended rather than waited on"), "\(answer)", sourceLocation: sourceLocation)
        let sessions = shards.map(\.session)
        let survivors = await InPlaceAnswerTests.onItsOwnThread {
            let exited = Date()
            var survivors = Self.left(in: sessions)
            while !survivors.isEmpty, Date().timeIntervalSince(exited) < Self.afterExit {
                Thread.sleep(forTimeInterval: 0.1)
                survivors = Self.left(in: sessions)
            }
            return survivors
        }
        #expect(survivors.isEmpty, "\(survivors) still running in the shard sessions \(sessions), \(Self.afterExit)s after swift-sure exited", sourceLocation: sourceLocation)
        #expect(shards.allSatisfy { kill($0.process, 0) == -1 && errno == ESRCH }, "a shard's test process of \(shards.map(\.process)) is still running", sourceLocation: sourceLocation)
    }
}
