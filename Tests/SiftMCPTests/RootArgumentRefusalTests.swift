//
// Copyright © Agulhas Labs
//

import ArgumentParser
@testable import SiftCLI
import SiftCore
import Testing

/// A positional `root=<path>` on the shell is the MCP spelling, refused before the lookup with the spelling that works.
struct RootArgumentRefusalTests {
    private static var expected: String {
        "root=/tmp/repo is the MCP spelling; on the CLI pass --root /tmp/repo"
    }

    @Test
    func everyLookupCommandRefusesIt() {
        #expect(Self.refusal(DigestCommand.self, ["root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(WhereCommand.self, ["root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(SearchCommand.self, ["root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(StringsCommand.self, ["root=/tmp/repo"]) == Self.expected)
    }

    @Test
    func digestRefusesItBesideARealTarget() {
        #expect(Self.refusal(DigestCommand.self, ["Alpha", "root=/tmp/repo"]) == Self.expected)
    }

    @Test
    func theRealOptionAndOrdinaryTargetsAreNotRefused() {
        #expect(Self.refusal(DigestCommand.self, ["Alpha", "--root", "/tmp/repo"]) == nil)
        #expect(Self.refusal(WhereCommand.self, ["rootless"]) == nil)
    }

    @Test
    func rootAfterTheTargetIsRefusedOnTheSinglePositionalCommands() {
        #expect(Self.refusal(WhereCommand.self, ["Foo", "root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(SearchCommand.self, ["kind:func", "root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(StringsCommand.self, ["x", "root=/tmp/repo"]) == Self.expected)
        #expect(Self.refusal(StringsCommand.self, ["x", "root=/tmp"]) == "root=/tmp is the MCP spelling; on the CLI pass --root /tmp")
    }

    @Test
    func anyOtherStrayArgumentIsRefusedAsUnexpected() {
        #expect(Self.refusal(WhereCommand.self, ["Foo", "Bar"])?.contains("Unexpected argument 'Bar'") == true)
        #expect(Self.refusal(StringsCommand.self, ["x", "y"])?.contains("Unexpected argument 'y'") == true)
    }

    @Test
    func aQueryThatOnlyLooksLikeTheSpellingRunsAsAQuery() {
        #expect(Self.refusal(StringsCommand.self, ["root=foo"]) == nil)
        #expect(Self.refusal(SearchCommand.self, ["name:root=foo"]) == nil)
    }

    @Test
    func flagsStillParseAfterTheTarget() throws {
        let command = try WhereCommand.parse(["Foo", "--decl", "--root", "/tmp/repo"])
        #expect(command.symbol == "Foo")
        #expect(command.declarationsOnly)
        let refs = try WhereCommand.parse(["Foo", "--refs", "--files"])
        #expect(refs.includeReferences && refs.filesOnly && refs.strays.isEmpty)
        let search = try SearchCommand.parse(["kind:func", "--count", "--offset", "3"])
        #expect(search.count && search.offset == 3)
        _ = try StringsCommand.parse(["x", "--root", "/tmp/repo"])
    }

    static func refusal<Command: ParsableCommand>(_: Command.Type, _ arguments: [String]) -> String? {
        do {
            _ = try Command.parse(arguments)
            return nil
        } catch {
            return Command.message(for: error)
        }
    }
}
