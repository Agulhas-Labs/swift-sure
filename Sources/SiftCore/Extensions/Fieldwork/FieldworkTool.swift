//
// Copyright © Agulhas Labs
//

import Fieldwork

public extension FieldworkTool {
    /// SwiftSure as Fieldwork names it: the backup beside a settings file SwiftSure rewrites is `<file>.bak-swift-sure`, the rule it installs is `swift-sure.md`, and the subcommands its hooks run are the ones ``SiftClaudeSetup/events`` registers.
    static let sift = FieldworkTool(name: SiftPaths.binaryName, hookSubcommands: SiftClaudeSetup.events.map(\.subcommand))
}

public extension FieldworkTool {
    /// The tool as `name`'s binary is known to Fieldwork: what an earlier release left behind is recognised through the name it shipped under.
    static func named(_ name: ProductName) -> FieldworkTool {
        FieldworkTool(name: name.binary, hookSubcommands: SiftClaudeSetup.events.map(\.subcommand))
    }

    /// The tool under every name this build answers to, current first.
    static var recognised: [FieldworkTool] {
        ProductName.recognised.map { named($0) }
    }
}
