//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// Assertion-light plumbing: one `tools/call` sent to a real server over pipes, and the text of its answer.
struct MCPToolCallDriver {
    static func answer(
        tool: String,
        arguments: [String: Any],
        root: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> String {
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
        func send(_ payload: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: payload)
            data.append(0x0A)
            toServer.fileHandleForWriting.write(data)
        }
        func next(sourceLocation: SourceLocation) async throws -> [String: Any] {
            let line = try #require(await responses.next(), sourceLocation: sourceLocation)
            return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], sourceLocation: sourceLocation)
        }
        try send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "test", "version": "0"]],
        ])
        _ = try await next(sourceLocation: sourceLocation)
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": tool, "arguments": arguments],
        ])
        let call = try await next(sourceLocation: sourceLocation)
        toServer.fileHandleForWriting.closeFile()
        _ = await task.value
        let result = try #require(call["result"] as? [String: Any], sourceLocation: sourceLocation)
        #expect(result["isError"] as? Bool == false, sourceLocation: sourceLocation)
        let content = try #require(result["content"] as? [[String: Any]], sourceLocation: sourceLocation)
        return try #require(content.first?["text"] as? String, sourceLocation: sourceLocation)
    }
}
