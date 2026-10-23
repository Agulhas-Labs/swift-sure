//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Covers the call-day stamps a scan keeps for the corrections of the line it just read.
struct CorrectionStampsPerLineTests {
    /// The stamps belong to the line just scanned, so a caller that never drains them finds only that line's.
    @Test
    func aLineStartsWithNoStampsFromTheLineBefore() {
        var state = TranscriptScanState()
        _ = TranscriptScan.events(line: TranscriptFixture.toolUse("mcp__swift-sure__digest", id: "a1", input: ["target": "Alpha"]), state: &state)
        _ = TranscriptScan.events(line: TranscriptFixture.toolResult(id: "a1", isError: true, text: "boom"), state: &state)
        let afterTheCorrection = state.correctionStamps.count

        _ = TranscriptScan.events(line: TranscriptFixture.toolUse("mcp__swift-sure__digest", id: "a2", input: ["target": "Beta"]), state: &state)
        let afterTheNextLine = state.correctionStamps.count

        _ = TranscriptScan.events(line: TranscriptFixture.toolResult(id: "a2", isError: true, text: "boom"), state: &state)

        #expect(afterTheCorrection == 1)
        #expect(afterTheNextLine == 0)
        #expect(state.correctionStamps.count == 1)
    }
}
