//
// Copyright © Agulhas Labs
//

import Fieldwork

/// The Fieldwork family `swift-sure install` carries on to: the tools whose installs it runs after its own.
public struct SiftFamily {
    private init() {}

    /// The Fieldwork family; SwiftSure skips itself, so the list is the same in every member.
    public static let members = [
        Family.Member(tool: .sift),
        Family.Member(tool: FieldworkTool(name: "simwalk")),
    ]
}
