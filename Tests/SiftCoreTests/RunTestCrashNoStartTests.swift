//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Where the run shows no signal line and no unfinished test has a known start, nothing places a trap line in the crash, so none is quoted.
///
/// Called on the value rather than through the parser: a start line and an unfinished name come from the same event readers, so no log makes the two disagree.
struct RunTestCrashNoStartTests {
    private static var trap: String {
        "Tests/Foo.swift:7: Fatal error: x"
    }

    private static func crash(unsignalledExit: Int32?) -> RunTestCrash {
        var crash = RunTestCrash()
        crash.unfinished = ["topples()"]
        crash.unsignalledExit = unsignalledExit
        crash.traps = [trap]
        crash.trapMarks = [RunTestCrash.Mark(process: 1, position: 9)]
        return crash
    }

    @Test
    func anUnfinishedTestWithNoKnownStartQuotesNoTrapWhereThereIsNoSignalLine() {
        #expect(Self.crash(unsignalledExit: 1).trapsOfTheCrash() == [])
    }

    @Test
    func aSignalledCrashWithNoKnownStartKeepsEveryTrap() {
        #expect(Self.crash(unsignalledExit: nil).trapsOfTheCrash() == [Self.trap])
    }
}
