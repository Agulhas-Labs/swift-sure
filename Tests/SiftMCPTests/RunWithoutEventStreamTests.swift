//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// Covers `swift-sure run --without` asking the `swift test` it runs for its event stream, as a plain `swift-sure run` does.
@Suite(.temporaryDirectories)
struct RunWithoutEventStreamTests {
    typealias Fixture = RunWithoutCommandTests.Fixture

    /// Both passes of a proof run are asked for the event stream: the run without the change and the run with it.
    ///
    /// The stand-in offers the option and records each pass that is handed it; a pass launched without the request for a stream is never handed one.
    @Test
    func bothPassesOfAProofRunAreAskedForTheEventStream() throws {
        let fixture = try Fixture()
        let asked = fixture.root.deletingLastPathComponent().appendingPathComponent("asked")

        let result = try fixture.sift(Fixture.proof, environment: ["SWIFT_SURE_TEST_EVENT_STREAM_LOG": asked.path])

        #expect(result.status == 0, "\(result.stdout)\(result.stderr)")
        let passes = (try? String(contentsOf: asked, encoding: .utf8))?.split(separator: "\n").count
        #expect(passes == 2, "\(result.stdout)")
    }
}
