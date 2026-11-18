//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the shared-value line when the only thing the failures have in common is Swift Testing's placeholder for an expectation it evaluated nothing in.
///
/// An expectation containing `try` that captures no operands prints `→ <not evaluated>`. That is the framework declining to give a value, so failures of different expectations printing it do not read one and the same value.
@Suite(.temporaryDirectories)
struct RunNotEvaluatedReadingTests {
    /// Forty failures of four different `try` expectations, every reading the placeholder.
    @Test
    func thePlaceholderIsNotAValueSharedAcrossDifferentExpectations() {
        let block = Self.shape(of: Self.messages(reading: "<not evaluated>")).rendered()

        #expect(!block.contains { $0.contains("read one and the same value") })
    }

    /// The same forty failures reading a real value still earn the line, so the placeholder is the only thing withheld.
    @Test
    func aRealValueSharedAcrossTheSameExpectationsIsStillNamed() {
        let block = Self.shape(of: Self.messages(reading: "42")).rendered()

        #expect(block.contains { $0.contains("40 of 40 failures read one and the same value") && $0.contains("→ 42") })
    }

    /// Current Swift Testing prints the placeholder on `↳` expansion lines beneath the message, not inline.
    @Test
    func thePlaceholderOnExpansionLinesIsNotAValueSharedAcrossDifferentExpectations() {
        let block = Self.shape(of: Self.expansionFailures(reading: "<not evaluated>")).rendered()

        #expect(!block.contains { $0.contains("read one and the same value") })
    }

    /// The same expansion-line form reading a real value still earns the line.
    @Test
    func aRealValueOnExpansionLinesIsStillNamed() {
        let block = Self.shape(of: Self.expansionFailures(reading: "42")).rendered()

        #expect(block.contains { $0.contains("40 of 40 failures read one and the same value") && $0.contains("→ 42") })
    }

    static func shape(of failures: [RunFailureShape.Failure]) -> RunFailureShape {
        RunFailureShape.of(failures, changedFiles: .of([]), accessibility: [])
    }

    /// Four expectations, ten failures each, every reading printed on `↳` lines beneath the message.
    static func expansionFailures(reading value: String) -> [RunFailureShape.Failure] {
        let kinds = [
            ("try bay.entries(after) == before", "try bay.entries(after)"),
            ("try crate.entries(after) == before", "try crate.entries(after)"),
            ("try pallet.count() == expected", "try pallet.count()"),
            ("try shelf.count() == expected", "try shelf.count()"),
        ]
        return (0 ..< 40).map { index in
            let (expression, operand) = kinds[index % kinds.count]
            let markedLines = ["\(expression) → \(value)", "\(operand) → \(value)"]
            return RunFailureShape.Failure(
                name: "aTestNamed\(index)()",
                location: "PalletTests.swift:\(index + 1):9",
                message: "Expectation failed: \(expression)",
                note: markedLines.joined(separator: " "),
                markedLines: markedLines
            )
        }
    }

    static func shape(of messages: [String]) -> RunFailureShape {
        RunFailureShape.of(
            messages.enumerated().map { index, message in
                RunFailureShape.Failure(name: "aTestNamed\(index)()", location: "PalletTests.swift:\(index + 1):9", message: message)
            },
            changedFiles: .of([]),
            accessibility: []
        )
    }

    /// Four expectations, ten failures each.
    static func messages(reading value: String) -> [String] {
        let kinds = [
            "(try bay.entries(after) → \(value)) == (before → \(value))",
            "(try crate.entries(after) → \(value)) == (before → \(value))",
            "(try pallet.count() → \(value)) == (expected → \(value))",
            "(try shelf.count() → \(value)) == (expected → \(value))",
        ]
        return (0 ..< 40).map { "Expectation failed: \(kinds[$0 % kinds.count])" }
    }
}
