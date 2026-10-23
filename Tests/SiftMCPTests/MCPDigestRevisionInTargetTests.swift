//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A digest target that carries the revision flag as a word is told where the revision goes: the `at` argument on the MCP face, its own target on the command line.
@Suite(.serialized, .temporaryDirectories)
struct MCPDigestRevisionInTargetTests {
    @Test func theMCPFaceTellsTheCallerToPassTheRevisionInTheAtArgument() async throws {
        let root = try MCPTestRepo.make(declaring: "Widget")

        let answer = try await MCPToolCallDriver.answer(tool: "digest", arguments: ["target": "Widget --at HEAD"], root: root)

        #expect(answer.contains("--at was not served: pass the revision in the at argument, not in target"), "\(answer)")
        #expect(!answer.contains("--at was not served: pass it as its own target"), "\(answer)")
    }

    @Test func theCommandLineKeepsItsWording() async throws {
        let root = try MCPTestRepo.make(declaring: "Widget")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()

        let answer = try engine.digest(targets: ["Widget --at HEAD"], options: DigestOptions())

        #expect(answer.contains("--at was not served: pass it as its own target"), "\(answer)")
    }
}
