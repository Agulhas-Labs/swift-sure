//
// Copyright © Agulhas Labs
//

@testable import SiftMCP
import Testing

/// The hook neither wraps nor rewrites a linter's non-lint subcommand, whose output is the answer.
struct LinterQuestionAdviceTests {
    @Test(arguments: ["swiftlint version", "swiftlint --version", "swiftlint rules", "swiftlint help", "swiftlint --help", "swiftlint docs"])
    func aNonLintSubcommandDrawsNoWrapping(command: String) {
        #expect(RunAdvice.suggestion(for: command) == nil)
        #expect(RunAdvice.inPlaceRewrite(of: command) == nil)
    }

    @Test
    func anotherBuildOnTheLineKeepsItsWrapping() throws {
        let call = try #require(RunAdvice.suggestion(for: "swiftlint version; swift test")).call

        #expect(call == "swiftlint version; swift-sure run -- swift test")
    }

    @Test
    func aLintRunIsStillWrapped() throws {
        #expect(try #require(RunAdvice.suggestion(for: "swiftlint lint --path Sources --help")).call == "swift-sure run -- swiftlint lint --path Sources --help")
    }
}
