//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// `swift-sure run --require-inventory` turns an unclean inventory into exit ``RunInventoryRequirement/exitCode``, and only that.
@Suite(.temporaryDirectories)
struct RunRequireInventoryTests {
    private static let flags = ["--require-inventory"]

    /// A run that lost a test, with the flag, exits 6 and the inventory line says why.
    @Test
    func anUncleanInventoryWithTheFlagExitsSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo"]), exiting: 0, flags: Self.flags)

        #expect(thrown == ExitCode(6))
        #expect(recorded.printed.contains("inventory: 3 declared, 2 reported — 1 never reported: GizmoTests/PalletTests/testThree()"))
    }

    /// The same run without the flag keeps the wrapped command's 0: the inventory stays a note.
    @Test
    func anUncleanInventoryWithoutTheFlagKeepsItsExitCode() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (_, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo"]), exiting: 0)

        #expect(thrown == nil)
    }

    /// A run that adds up exits as the command did.
    @Test
    func aCleanInventoryWithTheFlagExitsZero() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo", "testThree"]), exiting: 0, flags: Self.flags)

        #expect(thrown == nil)
        #expect(recorded.printed.contains("inventory: 3 declared, 3 reported"))
    }

    /// A failure of the command itself wins over 6.
    @Test
    func theCommandsOwnFailureBeatsSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (_, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne", "testTwo"]), exiting: 1, flags: Self.flags)

        #expect(thrown == ExitCode(1))
    }

    /// An unfiltered run that executed nothing exits 4, whatever the flag says of its inventory.
    @Test
    func exitFourBeatsSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let nothing = [
            "Test Suite 'All tests' started at 2026-10-02 06:49:41.667.",
            "Test Suite 'All tests' passed at 2026-10-02 06:49:41.668.",
            "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds",
        ]
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: nothing, exiting: 0, flags: Self.flags)

        #expect(thrown == ExitCode(RunTestSelector.exitCode))
        #expect(recorded.printed.contains("inventory: 3 declared, 0 reported"))
    }

    /// A run that printed no test at all has no inventory line today; under the flag it says nothing ran to reconcile and exits 6.
    @Test
    func aRunWithNoTestToReconcileSaysSoAndExitsSix() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: ["Build complete! (1.00s)"], exiting: 0, flags: Self.flags)

        #expect(thrown == ExitCode(6))
        #expect(recorded.printed.contains("inventory: not checked — no test ran to reconcile"))
    }

    /// A filtered run is one the inventory does not apply to: it keeps its code and says why nothing was checked.
    @Test
    func aFilteredRunKeepsItsExitCodeAndSaysTheInventoryDoesNotApply() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage()
        let (recorded, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: RunInventoryNoteTests.ended(["testOne"]), exiting: 0, extraArguments: ["--filter", "PalletTests/testOne"], flags: Self.flags)

        #expect(thrown == nil)
        #expect(recorded.printed.contains("inventory: not checked — the run was filtered, so it does not run the whole inventory"))
    }

    /// A green record made without the flag cannot stand for a run held to it, so the pair is refused.
    @Test
    func provedWithTheFlagIsRefused() throws {
        var command = try RunCommand.parse(["--proved", "--require-inventory", "--", "swift", "test"])
        command.output = RecordedOutput().output

        #expect(throws: ValidationError.self) { try command.run() }
    }
}
