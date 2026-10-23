//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// An `--only` whose enumeration lists nothing is never answered as a pass: xcodebuild's enumeration ignores `-only-testing` for a parameterised test, and a mistyped selector enumerates nothing too.
@Suite(.temporaryDirectories)
struct OnlyEnumeratesNothingTests {
    private func run(only: [String]) throws -> TestRun.Result {
        let root = try TemporaryDirectory.make("only-nothing")
        var fake = TestRunTests.Fake(root: root)
        fake.tests = []
        let request = TestRunRequest(
            scheme: "TestDemo",
            deviceTypeName: "iPhone 17",
            only: only,
            requestedShards: 2,
            workingDirectory: root,
            repositoryRoot: root,
            executable: root.appendingPathComponent("swift-sure")
        )
        return TestRun(request: request, environment: fake.environment(TestRunTests.Recorder())).run()
    }

    @Test
    func aSelectorThatEnumeratesNothingIsRefusedAndNamed() throws {
        let result = try run(only: ["Gizmo/Depot/restock()"])

        #expect(!result.answer.hasPrefix("✔"))
        #expect(result.answer.contains("Gizmo/Depot/restock()"))
        #expect(result.exitCode == 64)
        #expect(!result.answer.contains("--only Gizmo/Depot`"))
    }

    @Test
    func aParameterisedSelectorIsRefusedWithTheCommandThatRunsItsSuite() throws {
        let result = try run(only: ["Gizmo/Depot/restock(count:)"])

        #expect(!result.answer.hasPrefix("✔"))
        #expect(result.answer.contains("Gizmo/Depot/restock(count:)"))
        #expect(result.answer.contains("--only Gizmo/Depot`"))
        #expect(result.exitCode == 64)
    }

    @Test
    func noOnlyKeepsTheAnswerForAPlanWithNoTests() throws {
        let result = try run(only: [])

        #expect(result.answer.contains("✔ swift-sure test — the plan enumerated no tests"))
        #expect(result.exitCode == 0)
    }
}
