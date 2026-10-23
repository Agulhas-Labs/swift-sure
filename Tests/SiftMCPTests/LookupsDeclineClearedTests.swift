//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
@testable import SiftMCP
import Testing

/// A flag that answers the lookups question clears the remembered decline, and an end of input leaves it.
@Suite(.temporaryDirectories)
struct LookupsDeclineClearedTests {
    /// With the lookups rules already in the file, a flag still ends the earlier decline, since no question is reached to clear it.
    @Test(arguments: ["--allow-lookups", "--allow-run"])
    func aFlagClearsTheRecordWhereTheLookupsAreAlreadyAllowed(flag: String) throws {
        let machine = try Self.machine()
        _ = try machine.install(answer: "y")
        #expect(try machine.hasLookupRules())
        machine.record.write()

        _ = try machine.install([flag], answer: nil)

        #expect(!machine.record.exists)
    }

    /// An end of input is no answer, so a recorded decline stays.
    @Test
    func anEndOfInputLeavesTheRecord() throws {
        let machine = try Self.machine()
        _ = try machine.install(answer: "n")
        #expect(machine.record.exists)

        _ = try machine.install(answer: nil)

        #expect(machine.record.exists)
    }

    /// `--allow-run` adds the lookups with the runs, and so ends the decline.
    @Test
    func allowRunClearsTheRecordWhereTheLookupsAreMissing() throws {
        let machine = try Self.machine()
        _ = try machine.install(answer: "n")
        #expect(machine.record.exists)

        _ = try machine.install(["--allow-run"], answer: nil)

        #expect(!machine.record.exists)
        #expect(try machine.hasLookupRules())
    }

    fileprivate static func machine() throws -> Machine {
        let root = try TemporaryDirectory.make("decline-cleared")
        return Machine(settings: root.appendingPathComponent("settings.json"), state: root.appendingPathComponent("state"))
    }
}

private extension LookupsDeclineClearedTests {
    struct Machine {
        let settings: URL
        let state: URL

        var record: LookupsDeclineRecord {
            LookupsDeclineRecord(directory: state, environment: [:])
        }

        func install(_ arguments: [String] = [], answer: String?) throws -> [String] {
            var command = try InstallHookCommand.parse(["--settings", settings.path] + arguments)
            let terminal = AllowRunTerminal(answer: answer)
            command.output = RecordedOutput().output
            command.stateDirectory = state
            command.prompt = terminal.prompt(interactive: true)
            try command.run()
            return terminal.asked
        }

        func hasLookupRules() throws -> Bool {
            guard let data = try? Data(contentsOf: settings), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let allow = (object["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
            return LookupAllowRules.rules.allSatisfy(allow.contains)
        }
    }
}
