//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// The piped command the rewrite notice names adds `2>&1` only where the original does not already send standard error to standard output.
struct RunRewriteNoticePipedFormTests {
    @Test
    func aStatementThatSendsErrorToOutputIsNotDoubled() {
        #expect(RunRewrite.notice(forCommand: "swift test 2>&1").contains("`swift test 2>&1 | cat`"))
        #expect(RunRewrite.notice(forCommand: "swift test &> out.log").contains("`swift test &> out.log | cat`"))
        #expect(RunRewrite.notice(forCommand: "swift test |& tee x").contains("`swift test |& tee x | cat`"))
        #expect(!RunRewrite.notice(forCommand: "swift test 2>&1").contains("2>&1 2>&1"))
    }

    @Test
    func aStatementThatDoesNotGetsTheRedirection() {
        #expect(RunRewrite.notice(forCommand: "swift test --filter X").contains("`swift test --filter X 2>&1 | cat`"))
        #expect(RunRewrite.notice(for: ["swift", "test"]).contains("`swift test 2>&1 | cat`"))
    }
}
