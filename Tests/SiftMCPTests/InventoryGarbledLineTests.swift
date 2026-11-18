//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SiftCore
import Testing

/// A pass line spliced by two concurrent writers is a garbled report line, not a test that reported twice.
@Suite(.temporaryDirectories)
struct InventoryGarbledLineTests {
    private static var source: String {
        """
        import Testing

        struct PalletTests {
            @Test func anOrdinaryPass() {}
            @Test func countIsOne() {}
            @Test func dimLampWorks() {}
        }
        """
    }

    private static let splicedRun = [
        "◇ Test run started.",
        "✔ Test anOrdinaryPass() passed after 0.010 seconds.",
        "✔ Test anOrdinaryPass(ne() passed after 0.851 seconds.",
        "✔ Test dimLampWorks() passed after 0.001 seconds.",
        "✔ Test run with 3 tests in 1 suite passed after 0.900 seconds.",
    ]

    /// The spliced name is claimed by no test: it is named as garbled, the test whose line it swallowed is named as unreported, and nothing reads as reported twice.
    @Test
    func aSplicedPassLineIsGarbledNotReportedTwice() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        let (recorded, _) = try await RunInventoryNoteTests.run(in: repository, printing: Self.splicedRun, exiting: 0)

        let inventory = recorded.printed.split(separator: "\n").first { $0.hasPrefix("inventory:") }.map(String.init) ?? ""

        #expect(inventory.contains("1 report line garbled (output lines spliced?): anOrdinaryPass(ne()"), "\(recorded.printed)")
        #expect(inventory.contains("never reported: GizmoTests/PalletTests/countIsOne()"), "\(recorded.printed)")
        #expect(!recorded.printed.contains("reported more than once"), "\(recorded.printed)")
    }

    /// The reconciliation stays unclean: `--require-inventory` still refuses the run.
    @Test
    func aSplicedPassLineStillFailsRequireInventory() async throws {
        let repository = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        let (_, thrown) = try await RunInventoryNoteTests.run(in: repository, printing: Self.splicedRun, exiting: 0, flags: ["--require-inventory"])

        #expect(thrown == ExitCode(6))
    }

    /// What is garbled is the shape of the name, not any one name.
    @Test(arguments: [
        ("anOrdinaryPass(ne()", true),
        ("anOrdinaryPass(", true),
        ("a(b)(c)", true),
        ("anOrdinaryPass()", false),
        ("doublingIsEven(_:)", false),
        ("\"a (quoted) display name\"", false),
    ])
    func garbledNamesAreRecognisedByShape(name: String, garbled: Bool) {
        #expect(TestIdentifier.isGarbledSwiftTestingLogName(name) == garbled)
    }
}
