//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// Covers how `swift-sure install` hears its children: `claude mcp add` and `codex mcp` are started without the terminal, and what they say when they fail reaches the reader with its cause.
struct InstallSpawnTests {
    /// A `codex` failure with a `Caused by:` chain is reported with that chain, not only the line above it.
    @Test
    func aFailuresCauseComesWithIt() {
        let said = """
        Error: failed to load configuration

        Caused by:
            Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again.

        """
        let output = Subprocess.Output(succeeded: false, standardOutput: "", standardError: said)

        #expect(output.failureReason == "Error: failed to load configuration: Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again.")
    }

    /// A failure without a chain is its first line, and one that said nothing says so.
    @Test
    func aFailureWithoutACauseIsItsFirstLine() {
        let plain = Subprocess.Output(succeeded: false, standardOutput: "", standardError: "No MCP server named swift-sure\nmore\n")
        let silent = Subprocess.Output(succeeded: false, standardOutput: "", standardError: "")

        #expect(plain.failureReason == "No MCP server named swift-sure")
        #expect(silent.failureReason == "no output")
    }
}
