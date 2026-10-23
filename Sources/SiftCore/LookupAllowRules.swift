//
// Copyright © Agulhas Labs
//

import Foundation

/// The `Bash` allow rules `install-hook` offers for SwiftSure's four read-only lookups, so a context whose SwiftSure tools are deferred can call the CLI from Bash without a permission prompt.
///
/// A subagent gets the MCP tools as names only and pays a loading round trip before its first lookup; the same answers come from `swift-sure digest`, `where`, `search` and `strings` through Bash, which costs no loading step but would cost a prompt per call in a mode that asks. One rule per subcommand, in the legacy `prefix:*` form every Claude Code version reads, which the current one reads as `Bash(swift-sure digest *)`: the word after `swift-sure` is part of the match, so nothing else `swift-sure` runs is covered.
///
/// Each writes only SwiftSure's own index and caches: the `.swift-sure/` of the repository it names, which it lists in that repository's `.git/info/exclude`, and `~/.swift-sure`. None runs a program of the caller's choosing, edits the tracked tree, or takes a revision as anything but a revision. The `git` reads they start run with the repository's fsmonitor hook and its git hooks switched off (`-c core.fsmonitor=false -c core.hooksPath=/dev/null`), so a `core.fsmonitor` command set in its `.git/config` and a hook in its `core.hooksPath` or `.git/hooks` are never started, and a diff that produces content passes `--no-textconv`. A clean or smudge filter driver the user installed in their own config still runs where `git status` needs it; a clone carries none. Claude Code splits a line at `&&`, `||`, `;`, `|`, `|&`, `&` and newlines and requires a rule to match each part, so `swift-sure digest X && rm Y` still asks about `rm Y`, and a redirection's target is checked against the file rules whatever the command's rule says.
///
/// Written and removed as a block of their own, by the same install and uninstall that handle ``RunAllowRules``, with the same record-free removal of the last contiguous block.
public struct LookupAllowRules {
    /// The rules, in the order an install appends them.
    public static let rules = [
        "Bash(\(ProductName.current.binary) digest:*)",
        "Bash(\(ProductName.current.binary) where:*)",
        "Bash(\(ProductName.current.binary) search:*)",
        "Bash(\(ProductName.current.binary) strings:*)",
    ]

    /// One statement each rule covers, for asking whether the set holds in the settings Claude Code reads.
    public static let statements = ["\(ProductName.current.binary) digest .", "\(ProductName.current.binary) where X", "\(ProductName.current.binary) search kind:func", "\(ProductName.current.binary) strings X"]

    private static let block = AllowRuleBlock(rules: rules)

    /// The rules `data`'s `permissions.allow` list does not already hold, in the order an install would append them.
    public static func missing(from data: Data?) throws -> [String] {
        try block.missing(from: data)
    }

    /// `data` with the whole set appended to `permissions.allow` as one block, or `nil` where every rule is already there.
    public static func adding(to data: Data?) throws -> Data? {
        try block.adding(to: data)
    }

    /// `data` with the last contiguous, in-order block of the set taken out of `permissions.allow`, or `nil` where there is no such block.
    public static func removing(from data: Data?) throws -> Data? {
        try block.removing(from: data)
    }
}
