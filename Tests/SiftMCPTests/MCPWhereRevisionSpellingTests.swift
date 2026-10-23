//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// The server's own `where` tool, called with a revision, spells the pointer in its answer as a tool call: the glue between the tool and the engine, which the engine's own tests do not reach.
@Suite(.serialized, .temporaryDirectories)
struct MCPWhereRevisionSpellingTests {
    @Test func aWhereCallAtARevisionPointsAtTheFileAsAToolCall() async throws {
        let root = try MCPTestRepo.make(declaring: "Widget", extending: "Int")

        let answer = try await MCPToolCallDriver.answer(tool: "where", arguments: ["symbol": "Extensions", "at": "HEAD"], root: root)

        #expect(answer.contains(AtPointerSpellingTests.toolCall), "\(answer)")
        #expect(!answer.contains(" --at "), "\(answer)")
    }
}
