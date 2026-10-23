//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// Covers the `instructions` an `initialize` answer carries: the CLI does more than the four tools, said where a client that defers its tools still reads it.
@Suite(.temporaryDirectories)
struct InitializeInstructionsTests {
    private static func instructions(sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
        let root = try MCPTestRepo.make()
        let toServer = Pipe()
        let fromServer = Pipe()
        let server = MCPServer(
            input: toServer.fileHandleForReading,
            output: fromServer.fileHandleForWriting,
            defaultRoot: root,
            log: { _ in },
            registry: nil
        )
        let task = Task { await server.run() }
        var responses = FileHandleLines.lines(from: fromServer.fileHandleForReading).makeAsyncIterator()
        var request = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "test", "version": "0"]],
        ] as [String: Any])
        request.append(0x0A)
        toServer.fileHandleForWriting.write(request)
        let line = try #require(await responses.next(), sourceLocation: sourceLocation)
        toServer.fileHandleForWriting.closeFile()
        _ = await task.value
        let message = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], sourceLocation: sourceLocation)
        let result = try #require(message["result"] as? [String: Any], sourceLocation: sourceLocation)
        return try #require(result["instructions"] as? String, sourceLocation: sourceLocation)
    }

    @Test
    func initializeNamesTheTestVerbTheShardFlagTheRunWrapperAndHelp() async throws {
        let binary = ProductName.current.binary

        let text = try await Self.instructions()

        #expect(text.contains("`\(binary) test`"))
        #expect(text.contains("--shards"))
        #expect(text.contains("`\(binary) run --"))
        #expect(text.contains("`\(binary) --help`"))
    }
}
