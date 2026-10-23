//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers where the derived-data line sits in an answer that ends without the shard renderer: after the devices summary, as the last line.
@Suite(.temporaryDirectories)
struct WorktreeDerivedDataAnswerTests {
    private static func request(in root: URL, derivedDataPath: URL?) -> TestRunRequest {
        TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            derivedDataPath: derivedDataPath,
            requestedShards: 2,
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure")
        )
    }

    @Test
    func aFailedBuildEndsItsAnswerWithTheLineAfterTheDevicesSummary() throws {
        let root = try TemporaryDirectory.make("derived-answer")
        var fake = TestRunTests.Fake(root: root)
        fake.buildExit = 65
        let request = Self.request(in: root, derivedDataPath: root.appendingPathComponent(".swift-sure/DerivedData"))

        let result = TestRun(request: request, environment: fake.environment(TestRunTests.Recorder())).run()

        #expect(result.exitCode == 65)
        let lines = result.answer.split(separator: "\n").map(String.init)
        #expect(lines.last == WorktreeDerivedData.line(for: URL(fileURLWithPath: "/work/tree/.swift-sure/DerivedData")))
        let devices = try #require(lines.firstIndex(where: { $0.contains("simulators created, 2 deleted") }))
        #expect(devices == lines.count - 2)
    }

    @Test
    func aFailedBuildWithNoChosenPathNamesNoDirectory() throws {
        let root = try TemporaryDirectory.make("derived-answer")
        var fake = TestRunTests.Fake(root: root)
        fake.buildExit = 65

        let result = TestRun(request: Self.request(in: root, derivedDataPath: nil), environment: fake.environment(TestRunTests.Recorder())).run()

        #expect(!result.answer.contains("derived data"))
    }
}
