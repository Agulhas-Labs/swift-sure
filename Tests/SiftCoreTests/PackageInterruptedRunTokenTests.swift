//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// An interrupted package run still says which run it was, so its red is filed with the logs it left.
@Suite(.temporaryDirectories)
struct PackageInterruptedRunTokenTests {
    private func interrupted(shardsStarted: Bool, shards: Int?, sourceLocation: SourceLocation = #_sourceLocation) throws -> TestRunResult {
        let root = try TemporaryDirectory.make("interrupted-token")
        let run = PackageTestRun(packageDirectory: root, repositoryRoot: root, requestedShards: 2, shardTimeoutSeconds: nil, performanceCores: 1, runToken: "1a2b3c4d")
        run.cancel()
        return try #require(run.interruptedResult(shardsStarted: shardsStarted, shards: shards), sourceLocation: sourceLocation)
    }

    @Test
    func anInterruptionAfterTheShardsStartedCarriesTheTokenAndTheCount() throws {
        let result = try interrupted(shardsStarted: true, shards: 2)

        #expect(result.runToken == "1a2b3c4d")
        #expect(result.shards == 2)
        #expect(result.reconciled?.isGreen == false)
    }

    @Test
    func anInterruptionBeforeThePlanCarriesTheTokenAlone() throws {
        let result = try interrupted(shardsStarted: false, shards: nil)

        #expect(result.runToken == "1a2b3c4d")
        #expect(result.shards == nil)
    }
}
