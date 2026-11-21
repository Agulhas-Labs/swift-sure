//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// A refusal for changes left in place names every state directory they are under, not only the first path's.
struct StateDirectoryMixedListTests {
    @Test
    func aListUnderBothDirectoriesNamesBothInFirstSeenOrder() {
        let paths = [".sift/a", ".swift-sure/b", ".sift/c"]
        let uncommitted = SetAsideError.nothingUncommitted(pathspecs: ["Sources/"], matchesFiles: true, leftInPlace: paths, committedSince: nil).description
        let since = SetAsideError.nothingSince(pathspecs: ["Sources/"], since: "0123456789abcdef", matchesFiles: true, leftInPlace: paths).description

        #expect(uncommitted.contains("3 paths under .sift/ and .swift-sure/ —"))
        #expect(since.contains("3 paths under .sift/ and .swift-sure/ —"))
    }

    @Test
    func theOrderFollowsTheFirstPath() {
        #expect(SiftPaths.directoriesDescription(holding: [".swift-sure/a", ".sift/b"]) == ".swift-sure/ and .sift/")
    }
}
