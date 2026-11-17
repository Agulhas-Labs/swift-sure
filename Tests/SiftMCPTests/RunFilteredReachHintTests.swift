//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
import SiftCore
import Testing

/// Covers the line a one-filter run on a changed tree carries when a suite reaching the change was left out, through `RunCommand` itself: the wiring that hands the outcome to `FilteredRunReachHint`, not the lookup alone.
@Suite(.temporaryDirectories)
struct RunFilteredReachHintTests {
    private static var source: String {
        """
        import XCTest

        struct Pallet {}

        final class PalletTests: XCTestCase {
            func testA() {
                _ = Pallet()
            }
        }

        final class GadgetTests: XCTestCase {
            func testB() {
                _ = Pallet()
            }
        }
        """
    }

    private static let transcript = RunInventoryNoteTests.ended(["testA"])

    private static func dirty(_ repository: URL) throws {
        let file = repository.appendingPathComponent("Tests/GizmoTests/PalletTests.swift")
        try (source + "\nextension Pallet {\n    var size: Int { 1 }\n}\n").write(to: file, atomically: true, encoding: .utf8)
    }

    @Test
    func aOneFilterRunOnAChangedTreeCarriesTheLineWithTotalsAndExitCodeUnchanged() async throws {
        let changed = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        try Self.dirty(changed)
        let clean = try await RunInventoryNoteTests.indexedPackage(source: Self.source)
        let arguments = ["--filter", "PalletTests"]
        let (withLine, thrownWith) = try await RunInventoryNoteTests.run(in: changed, printing: Self.transcript, exiting: 0, extraArguments: arguments)
        let (without, thrownWithout) = try await RunInventoryNoteTests.run(in: clean, printing: Self.transcript, exiting: 0, extraArguments: arguments)

        let lines = withLine.printed.split(separator: "\n").map(String.init)
        let note = lines.filter { $0.hasPrefix("  filtered:") }
        #expect(note.count == 1, "\(withLine.printed)")
        #expect(note.first?.contains("1 suite reaching it did not run — run swift test --filter PalletTests --filter GizmoTests.GadgetTests") == true, "\(withLine.printed)")
        let totals = lines.firstIndex { $0.hasPrefix("totals:") }
        #expect(totals != nil && lines.firstIndex { $0.hasPrefix("  filtered:") } == totals.map { $0 + 1 }, "\(withLine.printed)")
        #expect(lines.filter { !$0.hasPrefix("  filtered:") && !$0.hasPrefix("raw:") } == without.printed.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("raw:") })
        #expect(thrownWith == thrownWithout)
        #expect(!without.printed.contains("filtered:"))
    }
}
