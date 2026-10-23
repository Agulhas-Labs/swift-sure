//
// Copyright © Agulhas Labs
//

import SiftCore

/// The one-line hint for a lookup whose single argument was read as an option.
struct DashQueryHint {
    private static let searching: Set<String> = ["strings", "search"]
    private static let looking: Set<String> = ["where", "digest"]
    private static let notQueries: Set<String> = ["-", "--", "-h", "--help"]

    /// The hint for these arguments (after the binary name), or nil when the shape is not a lone option-looking query.
    static func line(for arguments: [String]) -> String? {
        guard arguments.count == 2, let subcommand = arguments.first else { return nil }
        let token = arguments[1]
        guard token.hasPrefix("-"), !notQueries.contains(token) else { return nil }
        if searching.contains(subcommand) {
            return "\(token) was read as an option; to search for it, put -- first: \(ProductName.current.binary) \(subcommand) -- \"\(token)\""
        }
        if looking.contains(subcommand) {
            return "\(token) was read as an option; to look it up, put -- first: \(ProductName.current.binary) \(subcommand) -- \"\(token)\""
        }
        return nil
    }
}
