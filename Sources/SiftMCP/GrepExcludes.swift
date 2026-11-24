//
// Copyright © Agulhas Labs
//

import Foundation

/// The directories and file extensions a recursive search is told to leave out (`--exclude-dir`, `--exclude`), kept to the spellings that mean the same under `ugrep`, GNU grep and the system grep.
struct GrepExcludes: Equatable, Sendable {
    /// Names of directories skipped at any depth.
    var directories: Set<String> = []
    /// Extensions, without the dot, of files skipped.
    var extensions: Set<String> = []

    var isEmpty: Bool {
        directories.isEmpty && extensions.isEmpty
    }

    /// Reads the long flag `name` with its `value`, or `false` where this does not read it or the value is not a spelling whose meaning is certain.
    mutating func read(_ name: String, value: String?) -> Bool {
        guard let value else { return false }
        switch name {
        case "--exclude-dir":
            guard Self.isPlainDirectoryName(value) else { return false }
            directories.insert(value)
        case "--exclude":
            guard value.hasPrefix("*.") else { return false }
            let ext = String(value.dropFirst(2))
            guard Self.isPlainExtension(ext), ext != "swift" else { return false }
            extensions.insert(ext)
        default:
            return false
        }
        return true
    }

    /// The `files` (paths) whose names are not left out.
    func keeping(_ files: [String]) -> [String] {
        files.filter { file in
            let name = (file as NSString).lastPathComponent
            return !extensions.contains { name.hasSuffix("." + $0) }
        }
    }

    /// Whether the exclusions mean the same everywhere: they narrow a recursion, and none names an operand outright, where implementations differ on whether an exclusion applies.
    func isSafe(recursive: Bool, operands: [String]) -> Bool {
        isEmpty || recursive && !operands.contains { directories.contains(($0 as NSString).lastPathComponent) }
    }

    private static func isPlainDirectoryName(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return !value.contains { "/*?[]{}!\\".contains($0) }
    }

    private static func isPlainExtension(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
