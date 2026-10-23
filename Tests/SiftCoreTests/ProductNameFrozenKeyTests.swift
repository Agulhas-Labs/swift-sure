//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers the names that must not follow a rename: a word earlier hooks wrote and a key already in the usage log.
struct ProductNameFrozenKeyTests {
    @Test
    func theRewriteMarkerIsTheWordEarlierHooksWrote() {
        #expect(ProductName.rewriteMarker == "--sift-rewritten")
        #expect(RunRewrite.marker == "--sift-rewritten")
    }

    @Test
    func aRunTakesTheMarkerEarlierHooksWroteOff() {
        let (arguments, rewritten) = RunRewrite.unmarked(["swift", "test", "--sift-rewritten"])

        #expect(rewritten)
        #expect(arguments == ["swift", "test"])
    }

    @Test
    func theTestRunLogKeyIsThePersistedSpelling() {
        #expect(ProductName.testRunLogKey == "sift test")
    }
}
