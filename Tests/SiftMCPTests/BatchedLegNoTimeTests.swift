//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCLI
@testable import SiftMCP
import Testing

/// A compound line's Swift leg is judged alone only within the time the line's budget has left, and with none left it is withheld `overTime` without the leg being asked.
@Suite(.temporaryDirectories)
struct BatchedLegNoTimeTests {
    /// A whole read is the vehicle: a shell window beside another leg is `windowBeside` before any time is spent.
    @Test
    func aLegWithNoTimeLeftIsWithheldOverTimeAndHandedNoNote() async throws {
        let root = try await InPlaceAnswerTests.indexedRepository(padding: InPlaceAnswerTests.pastTheFloor)

        let decided = try await BatchedReadNoteTests.decide("cat Sources/App/Depot.swift; ls", in: root, timeBudget: 0)

        #expect(decided.json == nil)
        #expect(decided.logged == ["overTime"])
    }
}
