//
// Copyright © Agulhas Labs
//

import ArgumentParser
@testable import SiftCLI
import Testing

/// Covers the ways `--plan`, `--all-plans` and `--analyse` refuse each other, before anything is opened.
struct TestCommandPlanRefusalTests {
    private static func refusal(_ arguments: [String]) -> String? {
        do {
            _ = try TestCommand.parse(arguments)
            return nil
        } catch {
            return TestCommand.message(for: error)
        }
    }

    @Test
    func planAndAllPlansChooseThePlansTwoDifferentWays() {
        let message = Self.refusal(["--plan", "Default", "--all-plans"])

        #expect(message?.contains("--plan and --all-plans choose the plans two different ways") == true, "\(message ?? "nil")")
    }

    @Test(arguments: [
        ["--analyse", "--plan", "Default", "--plan", "Excluding"],
        ["--analyse", "--all-plans"],
    ])
    func analyseTakesOnePlanAndNoAllPlans(arguments: [String]) {
        let message = Self.refusal(arguments)

        #expect(message?.contains("it takes one --plan and no --all-plans") == true, "\(message ?? "nil")")
    }

    @Test
    func analyseWithOnePlanIsAccepted() {
        #expect(Self.refusal(["--analyse", "--plan", "Default"]) == nil)
    }
}
