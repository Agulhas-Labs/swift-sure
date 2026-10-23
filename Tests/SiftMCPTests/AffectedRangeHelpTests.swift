//
// Copyright © Agulhas Labs
//

@testable import SiftCLI
import Testing

/// `affected --from X` reads X up to HEAD, which is not what `swift-sure diff X` reads, and the help says so beside the spelling that does match.
struct AffectedRangeHelpTests {
    @Test
    func aLoneFromIsSaidToDifferFromDiffAndTheMatchingSpellingIsGiven() {
        let help = AffectedCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")

        #expect(help.contains("Unlike `swift-sure diff X`, a lone --from X is X..HEAD"))
        #expect(help.contains("--from X~1 --to X"))
    }
}
