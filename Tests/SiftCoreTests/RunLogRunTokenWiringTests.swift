//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Every log a sharded run opens carries the run's one token, because a path that drops it brings back the per-file count that lets one such run use up every place the next four runs were promised.
@Suite(.temporaryDirectories)
struct RunLogRunTokenWiringTests {
    private static func logNames(in root: URL) throws -> [String] {
        let runs = SiftPaths.cache(in: root).appendingPathComponent(RunLog.runsDirectoryName, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: runs.path).filter { $0.hasSuffix(".log") }.sorted()
    }

    /// The text between the last `-r` and the `.log` that closes a name, or `nil` for a log opened without a run.
    private static func token(of name: String) -> String? {
        guard name.hasSuffix(".log"), let marker = name.range(of: "-r", options: .backwards) else {
            return nil
        }
        return String(name[marker.upperBound...].dropLast(".log".count))
    }

    @Test
    func theXcodeBuildAndAShardAreOneRun() throws {
        let root = try TemporaryDirectory.make("run-token-xcode")
        let request = TestRunRequest(
            scheme: "Gizmo",
            deviceTypeName: "iPhone 17",
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure")
        )
        let children = SetAsideChildren()
        let environment = TestRunEnvironment.live(for: request, children: children)

        _ = try environment.launch(["/usr/bin/true"])
        let outcomes = environment.shardRunner(children).run([ShardRunner.Assignment(index: 0, argv: ["/usr/bin/true"], bound: 60)])

        let names = try Self.logNames(in: root)
        let tokens = Set(names.map { Self.token(of: $0) })

        #expect(outcomes.count == 1)
        #expect(names.count == 2, "\(names)")
        #expect(tokens.count == 1 && !tokens.contains(nil), "\(names)")
    }

    @Test
    func aPackageRunsBuildListingAndShardsCarryTheTokenItWasGiven() throws {
        let root = try TemporaryDirectory.make("run-token-package")
        let files = [
            "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(name: \"Gizmo\", targets: [.target(name: \"Gizmo\"), .testTarget(name: \"GizmoTests\", dependencies: [\"Gizmo\"])])\n",
            "Sources/Gizmo/Gizmo.swift": "public let gizmo = 1\n",
            "Tests/GizmoTests/GizmoTests.swift": "import XCTest\n@testable import Gizmo\n\nfinal class GizmoTests: XCTestCase {\n    func test() {\n        XCTAssertEqual(gizmo, 1)\n    }\n}\n",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let token = RunLog.newRunToken()

        let result = PackageTestRun(packageDirectory: root, repositoryRoot: root, requestedShards: 1, shardTimeoutSeconds: nil, performanceCores: 1, runToken: token).run()

        let names = try Self.logNames(in: root)

        #expect(result.exitCode == 0, "\(result.answer)")
        #expect(result.runToken == token)
        #expect(result.shards == 1)
        #expect(names.count >= 3, "\(names)")
        #expect(names.allSatisfy { Self.token(of: $0) == token }, "\(names) for \(token)")
    }
}
