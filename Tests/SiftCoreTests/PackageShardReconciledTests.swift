//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// What a real `PackageTestRun` of a fixture package hands the ledger in `TestRunResult.reconciled`: a green, a red, a shard SwiftSure cut short, and an interruption once the shards started.
@Suite(.temporaryDirectories)
struct PackageShardReconciledTests {
    private static var manifest: String {
        "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"Gizmo\"), .testTarget(name: \"GizmoTests\", dependencies: [\"Gizmo\"])])\n"
    }

    /// A package whose one test runs `body`.
    private static func package(named name: String, body: String) throws -> URL {
        let root = try TemporaryDirectory.make(name)
        let files = [
            "Package.swift": manifest,
            "Sources/Gizmo/Gizmo.swift": "public let gizmo = 1\n",
            "Tests/GizmoTests/GizmoTests.swift": "import Foundation\nimport XCTest\n@testable import Gizmo\n\nfinal class GizmoTests: XCTestCase {\n    func test() {\n        \(body)\n    }\n}\n",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static func run(_ root: URL, shardTimeoutSeconds: TimeInterval? = nil) -> PackageTestRun {
        PackageTestRun(packageDirectory: root, repositoryRoot: root, requestedShards: 1, shardTimeoutSeconds: shardTimeoutSeconds, performanceCores: 1)
    }

    @Test
    func aGreenRunReconcilesGreen() throws {
        let root = try Self.package(named: "reconciled-green", body: "XCTAssertEqual(gizmo, 1)")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = Self.run(root).run()

        #expect(result.exitCode == 0, "\(result.answer)")
        #expect(result.reconciled == TestRunResult.Reconciled(isGreen: true, stoppedBySift: false))
    }

    @Test
    func aFailingTestReconcilesRedWithoutSiftStoppingIt() throws {
        let root = try Self.package(named: "reconciled-red", body: "XCTAssertEqual(gizmo, 2)")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = Self.run(root).run()

        #expect(result.exitCode != 0, "\(result.answer)")
        #expect(result.reconciled == TestRunResult.Reconciled(isGreen: false, stoppedBySift: false))
    }

    @Test
    func aBuildThatFailedReconcilesNothing() throws {
        let root = try Self.package(named: "reconciled-build-failure", body: "let broken: Int = \"not an int\"")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = Self.run(root).run()

        #expect(result.exitCode != 0, "\(result.answer)")
        #expect(result.reconciled == nil)
    }

    @Test
    func aShardSiftEndedAtItsBoundReconcilesRedStoppedBySift() throws {
        let root = try Self.package(named: "reconciled-timeout", body: "Thread.sleep(forTimeInterval: 120)")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = Self.run(root, shardTimeoutSeconds: 3).run()

        #expect(result.reconciled == TestRunResult.Reconciled(isGreen: false, stoppedBySift: true), "\(result.answer)")
    }

    @Test
    func anInterruptionOnceTheShardsStartedReconcilesRedStoppedBySift() throws {
        let root = try TemporaryDirectory.make("reconciled-interrupted-marker")
        let marker = root.appendingPathComponent("started")
        let package = try Self.package(named: "reconciled-interrupted", body: "FileManager.default.createFile(atPath: \"\(marker.path)\", contents: nil); Thread.sleep(forTimeInterval: 120)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: package)
        }
        let run = Self.run(package)
        let canceller = Thread {
            let deadline = Date().addingTimeInterval(300)
            while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            run.cancel()
        }
        canceller.start()

        let result = run.run()

        #expect(result.exitCode == 130, "\(result.answer)")
        #expect(result.reconciled == TestRunResult.Reconciled(isGreen: false, stoppedBySift: true))
    }

    @Test
    func anInterruptionBeforeTheShardsStartedReconcilesNothing() throws {
        let package = try Self.package(named: "reconciled-early", body: "XCTAssertEqual(gizmo, 1)")
        defer { try? FileManager.default.removeItem(at: package) }
        let run = Self.run(package)
        run.cancel()

        let result = run.run()

        #expect(result.exitCode == 130, "\(result.answer)")
        #expect(result.reconciled == nil)
    }
}
