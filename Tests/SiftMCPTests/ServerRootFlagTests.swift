//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// The MCP server cannot tell where the agent's shell is, so a build command it prints names the lookup's root even where that root is the server's own working directory.
@Suite(.temporaryDirectories)
struct ServerRootFlagTests {
    @Test func anEngineTheServerOpensKnowsNoCallerDirectory() async throws {
        let root = try MCPTestRepo.make()
        let server = MCPServer(input: Pipe().fileHandleForReading, output: Pipe().fileHandleForWriting, defaultRoot: root, log: { _ in })

        let (engine, _) = try await server.engine(for: root, probing: nil, namedExplicitly: true)
        let freshness = try await engine.ensureFresh()
        let status = try engine.statusText(freshness: freshness)

        #expect(engine.callerDirectory == nil)
        #expect(status.contains("build one: swift-sure run --root "), "\(status)")

        engine.callerDirectory = root.path
        let fromTheRoot = try engine.statusText(freshness: freshness)
        #expect(!fromTheRoot.contains("--root"), "\(fromTheRoot)")
    }
}
