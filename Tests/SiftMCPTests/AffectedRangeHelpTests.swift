//
// Copyright © Agulhas Labs
//

@testable import SiftCLI
import Testing

/// `affected --from X` reads X up to HEAD, which is not X's own change, and the help says so beside the spelling that does match.
struct AffectedRangeHelpTests {
    @Test
    func aLoneFromIsSaidNotToBeTheCommitsOwnChangeAndTheMatchingSpellingIsGiven() {
        let help = AffectedCommand.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")

        #expect(help.contains("A lone --from X is X..HEAD"))
        #expect(help.contains("--from X~1 --to X"))
    }
}
