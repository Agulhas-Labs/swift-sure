//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// An argument a tool does not take is named in a note under the header, and the call is still answered.
@Suite(.temporaryDirectories)
struct IgnoredArgumentTests {
    private static func answer(tool: String, arguments: [String: Any], sourceLocation: SourceLocation = #_sourceLocation) async throws -> String {
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

    @Test
    func aStringsGlobIsNamedBesideTheHealedText() async throws {
        let text = try await Self.answer(tool: "strings", arguments: ["text": "Gizmo", "glob": "**/*Widget*"])

        #expect(text.contains("read text: as query:"))
        #expect(text.contains("ignored glob: — strings takes query, root."))
    }

    @Test
    func aWhereGlobIsNamedAndTheLookupAnswered() async throws {
        let text = try await Self.answer(tool: "where", arguments: ["symbol": "Alpha", "glob": "*.swift"])

        #expect(text.contains("ignored glob: — where takes symbol, root, refs, files, decl, offset."))
    }

    @Test
    func severalIgnoredKeysAreListedTogether() async throws {
        let text = try await Self.answer(tool: "strings", arguments: ["query": "Gizmo", "limit": 3, "glob": "*"])

        #expect(text.contains("ignored glob:, limit: — strings takes query, root."))
    }

    @Test
    func onlyDeclaredKeysAddNoNote() async throws {
        let strings = try await Self.answer(tool: "strings", arguments: ["query": "Gizmo"])

        #expect(!strings.contains("ignored"))
        let search = try await Self.answer(tool: "search", arguments: ["query": "kind:struct", "count": true])

        #expect(!search.contains("ignored"))
    }

    @Test
    func aHealedDonorKeyIsNotReportedIgnored() async throws {
        let text = try await Self.answer(tool: "strings", arguments: ["text": "Gizmo"])

        #expect(text.contains("read text: as query:"))
        #expect(!text.contains("ignored"))
    }

    @Test
    func aDonorKeyBesideTheKeyItWouldHealIsReportedIgnored() async throws {
        let text = try await Self.answer(tool: "strings", arguments: ["query": "Gizmo", "text": "Widget"])

        #expect(!text.contains("read text:"))
        #expect(text.contains("ignored text: — strings takes query, root."))
    }

    @Test
    func theDeclaredPropertiesMatchTheSchema() throws {
        for definition in MCPToolCatalog.definitions {
            let tool = try #require(definition["name"] as? String)
            let schema = try #require(definition["inputSchema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(Set(MCPToolCatalog.properties(of: tool)) == Set(properties.keys), "\(tool)")
        }
    }
}
