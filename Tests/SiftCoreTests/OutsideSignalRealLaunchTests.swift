//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A real package run whose one test signals its own shard from the inside: the answer names the signal as one SwiftSure did not send, and the run is not answered as interrupted.
@Suite(.temporaryDirectories)
struct OutsideSignalRealLaunchTests {
    private static var manifest: String {
        "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"Gizmo\"), .testTarget(name: \"GizmoTests\", dependencies: [\"Gizmo\"])])\n"
    }

    /// A package whose one test ends its own shard's session leader with `SIGTERM`, then waits to be ended.
    private static func package() throws -> URL {
        let root = try TemporaryDirectory.make("outside-signal-launch")
        let body = "kill(getsid(0), SIGTERM); Thread.sleep(forTimeInterval: 120)"
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

    @Test(.timeLimit(.minutes(8)))
    func aShardEndedBySomethingElseIsNamedAndTheRunIsNotInterrupted() throws {
        let root = try Self.package()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = PackageTestRun(packageDirectory: root, repositoryRoot: root, requestedShards: 1, shardTimeoutSeconds: nil, performanceCores: 1).run()

        #expect(result.answer.contains("by SIGTERM, which swift-sure did not send"), "\(result.answer)")
        #expect(!result.answer.contains("the run was interrupted"), "\(result.answer)")
        #expect(result.exitCode != 130, "\(result.answer)")
        #expect(result.reconciled == TestRunResult.Reconciled(isGreen: false, stoppedBySift: false), "\(result.answer)")
    }
}
