//
// Copyright © Agulhas Labs
//

/// Sites by the name asked for, with the spellings of each name in the files that hold them.
struct SpelledSites<Site: Sendable>: Sendable {
    var sites: [String: [Site]] = [:]
    var spellings = MemberSpellings()

    /// Takes `other`'s sites for every name it holds, and adds its spellings.
    mutating func update(with other: SpelledSites) {
        sites.merge(other.sites) { $1 }
        spellings.merge(other.spellings)
    }
}
