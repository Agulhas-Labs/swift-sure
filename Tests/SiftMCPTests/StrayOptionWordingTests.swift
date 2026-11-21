//
// Copyright © Agulhas Labs
//

@testable import SiftCLI
import Testing

/// An unknown option on `where`, `search` or `strings` reads as one, with the closest of the command's own options when it is a near miss.
struct StrayOptionWordingTests {
    @Test
    func anUnknownOptionIsNamedAsOneOnEachCommand() {
        for text in [
            RootArgumentRefusalTests.refusal(WhereCommand.self, ["Gizmo", "--bogus"]),
            RootArgumentRefusalTests.refusal(SearchCommand.self, ["kind:func", "--bogus"]),
            RootArgumentRefusalTests.refusal(StringsCommand.self, ["gizmo", "--bogus"]),
        ] {
            #expect(text?.contains("Unknown option '--bogus'") == true)
            #expect(text?.contains("Did you mean") == false)
        }
    }

    @Test
    func aNearMissSuggestsTheOptionItIsClosestTo() {
        for text in [
            RootArgumentRefusalTests.refusal(WhereCommand.self, ["Gizmo", "--roo", "x"]),
            RootArgumentRefusalTests.refusal(SearchCommand.self, ["kind:func", "--roo"]),
            RootArgumentRefusalTests.refusal(StringsCommand.self, ["gizmo", "--roo"]),
        ] {
            #expect(text?.contains("Unknown option '--roo'. Did you mean '--root'?") == true)
        }
    }

    @Test
    func aPlainWordIsStillAnUnexpectedArgument() {
        #expect(RootArgumentRefusalTests.refusal(WhereCommand.self, ["Gizmo", "Bar"])?.contains("Unexpected argument 'Bar'") == true)
    }
}
