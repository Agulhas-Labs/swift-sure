//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// The refusal the command line gives a positional `root=<path>`: the MCP face's spelling of the root, which the shell reads as part of the target and so misses on.
///
/// Refused before the lookup, with the spelling that works, since the answer a miss would give names no such symbol and sends the caller hunting for one.
public struct RootArgumentRefusal {
    /// The message when any of `targets` is written `root=<path>`, otherwise `nil`.
    ///
    /// Only a remainder that is a path counts (it starts with `/` or `~`, or names an existing directory), so a query such as `root=foo` stays a query.
    public static func message(targets: [String]) -> String? {
        guard let path = targets.compactMap(Self.path(in:)).first else { return nil }
        return "root=\(path) is the MCP spelling; on the CLI pass --root \(ShellWord.quoted(path))"
    }

    private static func path(in target: String) -> String? {
        guard target.hasPrefix("root=") else { return nil }
        let path = String(target.dropFirst("root=".count))
        if path.hasPrefix("/") || path.hasPrefix("~") {
            return path
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : nil
    }
}
