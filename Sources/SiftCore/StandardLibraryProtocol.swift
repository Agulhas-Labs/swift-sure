//
// Copyright © Agulhas Labs
//

/// One standard-library protocol in ``StandardLibraryRequirements``: what a conforming type may write to satisfy it.
struct StandardLibraryProtocol {
    /// The protocols it inherits, whose own entries the witness check follows.
    let inherits: [String]
    /// The labeled names of every requirement a member may satisfy, customization points and its inherited protocols' included.
    let members: Set<String>
    /// The associated types a nested type or typealias may satisfy, its inherited protocols' included.
    let associatedTypes: Set<String>

    init(inherits: [String] = [], members: Set<String>, associatedTypes: Set<String> = []) {
        self.inherits = inherits
        self.members = members
        self.associatedTypes = associatedTypes
    }
}
