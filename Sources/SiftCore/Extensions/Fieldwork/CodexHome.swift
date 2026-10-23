//
// Copyright © Agulhas Labs
//

import Fieldwork

public extension AgentPaths.CodexHome {
    /// The line every answer opens with.
    var line: String {
        "codex home: \(directory.path) (\(source))"
    }
}
