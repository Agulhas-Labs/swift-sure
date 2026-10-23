//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// The `uses:` refusal as the MCP `search` tool serves it: an error whose one line says what to do instead.
@Suite(.temporaryDirectories)
struct UsesMagicLiteralServedRefusalTests {
    private static func search(_ query: String, in root: URL, sourceLocation: SourceLocation = #_sourceLocation) async throws -> (text: String, isError: Bool) {
        let toServer = Pipe()
        let fromServer = Pipe()
        let server = MCPServer(input: toServer.fileHandleForReading, output: fromServer.fileHandleForWriting, defaultRoot: root, log: { _ in })
        let task = Task { await server.run() }
        var responses = FileHandleLines.lines(from: fromServer.fileHandleForReading).makeAsyncIterator()
        func send(_ payload: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: payload)
            data.append(0x0A)
            toServer.fileHandleForWriting.write(data)
        }
        try send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "test", "version": "0"]],
        ])
        _ = await responses.next()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "search", "arguments": ["query": query]]])
        let line = try #require(await responses.next(), sourceLocation: sourceLocation)
        toServer.fileHandleForWriting.closeFile()
        _ = await task.value
        let response = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], sourceLocation: sourceLocation)
        let result = try #require(response["result"] as? [String: Any], sourceLocation: sourceLocation)
        let content = try #require(result["content"] as? [[String: Any]], sourceLocation: sourceLocation)
        return try (#require(content.first?["text"] as? String, sourceLocation: sourceLocation), result["isError"] as? Bool == true)
    }

    @Test
    func searchServesTheRefusalAsAnErrorNamingTheRoute() async throws {
        let root = try MCPTestRepo.make()

        let answer = try await Self.search("uses:#filePath", in: root)

        #expect(answer.isError)
        #expect(answer.text.contains("uses:#filePath — uses: matches names a body references; #filePath is a magic literal or macro, which it cannot match; to find where it is written, git grep '#filePath'"), "\(answer.text)")
        #expect(!answer.text.contains("no declarations match"), "\(answer.text)")
    }
}
