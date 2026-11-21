//
// Copyright © Agulhas Labs
//

@testable import SiftCLI
import Testing

/// The `--root` the refusal suggests for a `root=~/…` target is one the shell expands, since the option itself does no tilde expansion.
struct RootArgumentTildeTests {
    @Test
    func aLeadingTildeSlashStaysOutsideTheQuotes() {
        #expect(RootArgumentRefusalTests.refusal(WhereCommand.self, ["Foo", "root=~/x"]) == "root=~/x is the MCP spelling; on the CLI pass --root ~/x")
    }

    @Test
    func theRestOfTheHomePathIsQuotedWhereItNeedsIt() {
        #expect(RootArgumentRefusalTests.refusal(WhereCommand.self, ["Foo", "root=~/my dir"]) == "root=~/my dir is the MCP spelling; on the CLI pass --root ~/'my dir'")
    }

    @Test
    func aBareTildeStaysATilde() {
        #expect(RootArgumentRefusalTests.refusal(WhereCommand.self, ["Foo", "root=~"]) == "root=~ is the MCP spelling; on the CLI pass --root ~")
    }
}
