//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Covers the MCP face of the `--files` closing hint.
@Suite(.temporaryDirectories)
struct AnswerHintMCPTests {
    /// `files: true` on the `where` tool ends a listing that names a file with the same line the CLI prints.
    @Test
    func theFilesViewEndsWithTheDropLine() async throws {
        let root = try MCPTestRepo.make()

        let registry = try RootsRegistry(fileURL: TemporaryDirectory.make("roots").appendingPathComponent("roots.json"))
        let server = try AnswerHeaderTests.Server(defaultRoot: root, registry: registry)

        let files = try await server.call("where", ["symbol": "Alpha", "files": true])
        await server.close()

        #expect(files.contains("files naming "), "\(files)")
        #expect(files.hasSuffix("\ndrop --files for each reference's line"), "\(files)")
    }
}
