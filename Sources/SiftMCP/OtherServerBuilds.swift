//
// Copyright © Agulhas Labs
//

import SiftCore

/// The builds made through other MCP servers that one read of a transcript follows: those waiting on a result, the repositories edited so far, and for each, the newest since its last edit whose result carried neither a success line nor a failure line.
///
/// A green one clears the edits under a path its input names, so a build of one repository never clears another's; where the input names no path at all and the context has edited only one repository, it clears that one's. A path outside every repository names none, so a build of an unrelated project clears nothing. An edit after it stands.
struct OtherServerBuilds {
    /// The calls waiting on their result, by tool-use id.
    private(set) var pending: [String: OtherServerBuild] = [:]
    /// By repository root, the newest call since that repository's last edit whose result was no error but carried neither a success line nor a failure line: a call stands for the repositories its input names, or where it names no path, every one edited before it.
    private(set) var unconfirmed: [String: OtherServerBuild] = [:]
    private var editedRoots: Set<String> = []

    /// Holds the call in `block` until its result arrives, where it is a build made through another server.
    mutating func note(call block: [String: Any], recognising products: [ProductName]) {
        guard let id = block["id"] as? String, let build = OtherServerBuild(call: block, recognising: products) else { return }
        pending[id] = build
    }

    /// An edit landed in the repository at `root`, or in none: no build before it vouches for that repository.
    mutating func noteEdit(in root: String?) {
        guard let root else { return }
        editedRoots.insert(root)
        unconfirmed[root] = nil
    }

    /// The repositories whose edits the result `block` of call `id` clears, where it answers a held build with a green result, or `nil` where it clears none; `root` names the repository a directory is in.
    mutating func settle(result block: [String: Any], id: String, failed: Bool, root: (String) -> String?) -> Set<String>? {
        guard let build = pending.removeValue(forKey: id), !failed, let text = OtherServerBuild.text(ofResult: block) else { return nil }
        let verdict = OtherServerBuild.verdict(of: text, testRun: build.isTest)
        let named = Set(build.paths.compactMap { root(OtherServerBuild.directory(of: $0)) })
        guard verdict.isGreen else {
            if verdict.isSilent {
                for repository in build.paths.isEmpty ? editedRoots : named {
                    unconfirmed[repository] = build
                }
            }
            return nil
        }
        let cleared = build.paths.isEmpty && editedRoots.count == 1 ? editedRoots : named
        for repository in cleared {
            unconfirmed[repository] = nil
        }
        return cleared
    }
}
