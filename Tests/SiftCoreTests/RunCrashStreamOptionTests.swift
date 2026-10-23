//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A signal line the answer quotes never carries the option the launcher inserted to read the run's event stream, whose path is gone by the time anyone reads the answer.
struct RunCrashStreamOptionTests {
    private static var inserted: String {
        "--event-stream-output-path /Users/dev/Pallet/.swift-sure/run-events/0F5C1C0E-0000-4000-8000-000000000000/events.jsonl"
    }

    private static func answer(executable: String, inserting: String?) -> String {
        let log = """
        Building for debugging...
        error: Process '\(executable) --test-bundle-path /Users/dev/Pallet/.build/out/Products/Debug/PalletTests.xctest \(inserted) --testing-library swift-testing' exited with unexpected signal code 5

        """
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        filter.insertedStreamOption = inserting
        filter.consume(Data(log.utf8))
        let report = filter.finish(exitCode: 1)
        return RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Pallet")).render(report, exitCode: 1, logURL: nil)
    }

    /// A process the crash reader does not know falls back to the error line itself, which is where the quoted argv reaches the answer.
    @Test
    func aQuotedSignalLineLeavesTheInsertedStreamOptionOut() {
        let answer = Self.answer(executable: "/usr/bin/other-helper", inserting: Self.inserted)

        #expect(answer.contains("error: Process '/usr/bin/other-helper --test-bundle-path"))
        #expect(answer.contains("PalletTests.xctest --testing-library swift-testing' exited with unexpected signal code 5"))
        #expect(!answer.contains("--event-stream-output-path"))
        #expect(!answer.contains("run-events"))
    }

    @Test
    func anOptionTheCallerPassedItselfIsKept() {
        let answer = Self.answer(executable: "/usr/bin/other-helper", inserting: nil)

        #expect(answer.contains("--event-stream-output-path"))
    }
}
