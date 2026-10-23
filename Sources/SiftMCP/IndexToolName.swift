//
// Copyright © Agulhas Labs
//

import SiftCore

/// The names this server's tools go by outside this process — in a transcript, in a hook payload, in a `PreToolUse` matcher.
///
/// A plugin server whose name ends in the server's — `my_sift`, or `my.sift` or `my swift-sure` before the harness sanitises it to `my_sift` — is indistinguishable from this one by name alone (`mcp__plugin_acme_my_sift__digest`), because the harness's spelling joins the plugin and the server with the same `_` a name can contain; it is accepted as this server's.
///
/// One place, because the readers are as far apart as this package gets and every one of them has to agree: the transcript scanner deciding whether a recorded call was an index call, and the `PreToolUse` hook deciding whether the call in front of it is this context taking the advice. A name known to one of those and not the others is not a disagreement anyone sees — it is a rule that silently does not apply.
public struct IndexToolName {
    /// The name this server is registered under, which is how the harness reports on it — a server that failed to start, say — as distinct from the tools it serves.
    public static var server: String {
        ProductName.current.mcpServer
    }

    /// The prefix this server's calls appear under now: the harness's spelling of a tool from the server above.
    public static var prefix: String {
        ProductName.current.toolPrefix
    }

    /// The tools as anything outside this process has to spell them — an agent's `tools:` allowlist, a settings file.
    ///
    /// Built from the catalog the server actually advertises rather than written out beside it, so a tool added there cannot leave a check asking after a list that is no longer the list.
    public static var qualified: [String] {
        MCPToolCatalog.tools(loadUpFront: false).compactMap { $0["name"] as? String }.map { prefix + $0 }
    }

    /// The same tools as the harness spells them when a plugin named for the tool ships the server: `mcp__plugin_<plugin>_<server>__<tool>`.
    public static var pluginQualified: [String] {
        let product = ProductName.current
        let prefix = ProductName.pluginToolPrefix + product.binary + "_" + product.pluginServerSegment + "__"
        return MCPToolCatalog.tools(loadUpFront: false).compactMap { $0["name"] as? String }.map { prefix + $0 }
    }

    /// The tool named by an MCP call of this server's, under any name this build answers to, or `nil` for anyone else's.
    public static func tool(named name: String) -> String? {
        tool(named: name, recognising: ProductName.recognised)
    }

    /// The tool named by an MCP call of a server in `products`, or `nil` for anyone else's.
    ///
    /// Two spellings count: `mcp__<server>__<tool>`, and the one the harness gives a server a plugin ships, `mcp__plugin_<plugin>_<server>__<tool>`, read at the last `_<server>__` so a plugin name that contains the server's is not cut short. A name that merely begins with the server's letters is not the server.
    public static func tool(named name: String, recognising products: [ProductName]) -> String? {
        for product in products {
            if name.hasPrefix(product.toolPrefix) {
                return String(name.dropFirst(product.toolPrefix.count))
            }
            guard name.hasPrefix(ProductName.pluginToolPrefix) else { continue }
            let separator = "_" + product.pluginServerSegment + "__"
            let body = name.dropFirst(ProductName.pluginToolPrefix.count)
            if let range = body.ranges(of: separator).last, range.lowerBound > body.startIndex {
                return String(body[range.upperBound...])
            }
        }
        return nil
    }

    /// Whether `name` is the harness's name for this server, as it reports a failure or a pending connection, under any name this build answers to, bare or as a plugin ships it.
    public static func isServer(_ name: String) -> Bool {
        isServer(name, recognising: ProductName.recognised)
    }

    /// Whether `name` is the harness's name for the server of a product in `products`.
    public static func isServer(_ name: String, recognising products: [ProductName]) -> Bool {
        products.contains { product in
            name == product.mcpServer
                || name.hasPrefix("plugin")
                && (name.contains(":") ? name.hasSuffix(":" + product.mcpServer) : name.hasSuffix("_" + product.pluginServerSegment))
        }
    }

    /// The tool named by a Cursor MCP call of this server's, or `nil` for anyone else's and wherever that cannot be told.
    ///
    /// Cursor spells an MCP call `MCP:<tool>` with no server in it, so another server's `digest` reads the same, and the arguments decide: every one a name this server's tool takes, its required ones present as text, and a `digest` naming a target.
    public static func tool(namedByCursor name: String, input: [String: Any]) -> String? {
        guard name.hasPrefix(cursorPrefix) else { return nil }
        let tool = String(name.dropFirst(cursorPrefix.count))
        guard let schema = MCPToolCatalog.tools(loadUpFront: false).first(where: { $0["name"] as? String == tool })?["inputSchema"] as? [String: Any],
              let properties = schema["properties"] as? [String: Any],
              Set(input.keys).isSubset(of: Set(properties.keys).union(MCPToolCatalog.unlistedArguments[tool] ?? [])),
              (schema["required"] as? [String] ?? []).allSatisfy({ input[$0] is String })
        else {
            return nil
        }
        guard tool == "digest" else { return tool }
        return input["target"] is String || input["targets"] is [String] ? tool : nil
    }

    private static var cursorPrefix: String {
        "MCP:"
    }
}
