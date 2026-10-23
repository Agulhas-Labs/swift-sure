//
// Copyright © Agulhas Labs
//

import Foundation

/// One relaunch of a test bundle that `xcodebuild` announced with `Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.`
///
/// The relaunched process prints a Swift Testing summary of its own pass, so a log can end on a `passed` sentence over a handful of tests beside `** TEST FAILED **`. This records what the log shows at the marker, so the answer counts both passes under their own names.
public struct RunRestart: Sendable, Equatable {
    /// The tests the log shows started and never ended when the marker arrived, as the answer names them; empty where there is no such test.
    public let open: [String]
    /// How many Swift Testing tests reported in the pass this restart ended, counting from the previous restart or the start of the log.
    public let reported: Int
    /// How many Swift Testing summary lines the log had printed before the marker.
    public let summariesBefore: Int
    /// How many XCTest tests reported an ending in the pass this restart ended, counting from the previous restart or the start of the log.
    public let xctestReported: Int
    /// Whether a Swift Testing test was open when the marker arrived.
    public let swiftTestingOpen: Bool
    /// Whether an XCTest test was open when the marker arrived.
    public let xctestOpen: Bool
    /// The trap lines (`File.swift:12: Fatal error: …`) the dead process printed after the earliest open test started, or since the previous restart where no test was open.
    public let traps: [String]

    public init(open: [String], reported: Int, summariesBefore: Int, xctestReported: Int = 0, swiftTestingOpen: Bool = false, xctestOpen: Bool = false, traps: [String] = []) {
        self.open = open
        self.reported = reported
        self.summariesBefore = summariesBefore
        self.xctestReported = xctestReported
        self.swiftTestingOpen = swiftTestingOpen
        self.xctestOpen = xctestOpen
        self.traps = traps
    }

    /// Whether `line` is the marker `xcodebuild` prints before relaunching a bundle.
    static func isMarker(_ line: String) -> Bool {
        line.hasPrefix("Restarting after unexpected exit, crash, or test timeout")
    }
}
