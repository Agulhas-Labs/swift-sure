//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// The built `swift-sure test --shards 2`, signalled with `SIGTERM` while both shards are mid-run: it exits 143, answers that the run was interrupted, and leaves no shard process running.
@Suite(.temporaryDirectories)
struct InterruptedShardsEndedTests {
    /// How long a wait for an outcome goes on before the outcome counts as never coming.
    private static let patience: TimeInterval = 480

    /// A package of two test classes, each of which records its process id in `markers` and then waits to be ended.
    private static func package(recordingIn markers: URL) throws -> URL {
        let root = try TemporaryDirectory.make("interrupted-shards")
        let manifest = "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"Gizmo\"), .testTarget(name: \"GizmoTests\", dependencies: [\"Gizmo\"])])\n"
        var files = ["Package.swift": manifest, "Sources/Gizmo/Gizmo.swift": "public let gizmo = 1\n"]
        for name in ["Alpha", "Beta"] {
            let marker = markers.appendingPathComponent(name).path
            files["Tests/GizmoTests/\(name)Tests.swift"] = "import Foundation\nimport XCTest\n\nfinal class \(name)Tests: XCTestCase {\n    func test() {\n        FileManager.default.createFile(atPath: \"\(marker)\", contents: Data(\"\\(getpid())\".utf8))\n        Thread.sleep(forTimeInterval: 300)\n    }\n}\n"
        }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    /// The pid a test wrote to `file`, once it has.
    private static func pid(in file: URL) -> pid_t? {
        (try? String(contentsOf: file, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    @Test(.timeLimit(.minutes(10)))
    func aSignalledRunExitsInterruptedAndLeavesNoShardRunning() async throws {
        let sift = try #require(BuiltExecutable.sift, "no `swift-sure` built beside the test bundle, at \(BuiltExecutable.expected.path)")
        let scratch = try TemporaryDirectory.make("interrupted-shards-scratch")
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
        try #require(initialise.terminationStatus == 0)
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
            for file in markerFiles {
                if let child = Self.pid(in: file) {
                    kill(child, SIGKILL)
                }
            }
        }
        // Until both shards' tests are running, or the run has ended without starting them; polled off the concurrency pool, which a loaded suite can hold.
        await InPlaceAnswerTests.onItsOwnThread {
            let started = Date()
            while markerFiles.contains(where: { Self.pid(in: $0) == nil }), process.isRunning, Date().timeIntervalSince(started) < Self.patience {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let shards = try markerFiles.map { try #require(Self.pid(in: $0), "a shard's test never started: \((try? String(contentsOf: output, encoding: .utf8)) ?? "")") }

        kill(process.processIdentifier, SIGTERM)
        await InPlaceAnswerTests.onItsOwnThread { process.waitUntilExit() }
        let answer = (try? String(contentsOf: output, encoding: .utf8)) ?? ""

        #expect(process.terminationReason == .exit && process.terminationStatus == 143, "ended \(process.terminationReason.rawValue) with \(process.terminationStatus): \(answer)")
        #expect(answer.contains("the run was interrupted, so its shards were ended rather than waited on"), "\(answer)")
        let gone = await InPlaceAnswerTests.onItsOwnThread {
            let stopped = Date()
            while Date().timeIntervalSince(stopped) < 60 {
                if shards.allSatisfy({ kill($0, 0) == -1 && errno == ESRCH }) {
                    return true
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return false
        }
        #expect(gone, "a shard process of \(shards) is still running")
    }
}
