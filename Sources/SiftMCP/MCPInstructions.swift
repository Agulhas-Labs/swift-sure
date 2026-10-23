//
// Copyright © Agulhas Labs
//

import SiftCore

/// What `initialize` tells a client about the binary beside the four tools: the CLI does more than they do.
///
/// A client that defers MCP tools sees only their names, and the primer and the rule load only in a Swift repository or at a Swift file. The server's `instructions` reach the model whenever the server is registered (Docs/Design.md §4), so the one fact the tools cannot show is said here: the other commands exist.
struct MCPInstructions {
    static var text: String {
        let binary = ProductName.current.binary
        return "The \(binary) CLI does more: `\(binary) test` shards tests across processes or simulators (`--shards N`), `\(binary) run -- <build or test>` returns failures, `\(binary) --help` lists the rest."
    }
}
