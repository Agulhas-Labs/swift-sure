//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// No spawn in the tree is made without attributes: a child spawned with none receives a copy of every descriptor of its parent, including the write end of a pipe some other thread is reading a process's output from.
struct SpawnAttributesTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The directories whose Swift files are read, repository-relative.
    private static let scanned = ["Sources", "Tests"]

    /// The calls of the spawn functions.
    private static var call: Regex<Substring> {
        /\bposix_spawnp?[(]/
    }

    /// Every Swift file under the scanned directories, with its text — the fixtures directories hold sources the suites parse, not code that runs, and this file's own samples are spawns on purpose.
    private static func sources() throws -> [(path: String, text: String)] {
        let manager = FileManager.default
        var found: [(path: String, text: String)] = []
        for directory in scanned {
            let base = root.appendingPathComponent(directory)
            guard let walk = manager.enumerator(at: base, includingPropertiesForKeys: nil) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            for case let url as URL in walk {
                if url.lastPathComponent == "Fixtures" {
                    walk.skipDescendants()
                } else if url.pathExtension == "swift", url.standardizedFileURL != URL(fileURLWithPath: #filePath).standardizedFileURL {
                    let path = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                    try found.append((path, String(contentsOf: url, encoding: .utf8)))
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The arguments of the call whose opening parenthesis is at `open`, split at the commas outside any nesting.
    static func arguments(in text: String, after open: String.Index) -> [String] {
        var depth = 0
        var current = ""
        var result: [String] = []
        var index = open
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if character == "(" || character == "[" {
                depth += 1
                if depth == 1 {
                    continue
                }
            } else if character == ")" || character == "]" {
                depth -= 1
                if depth == 0 {
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    return result
                }
            } else if character == ",", depth == 1 {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }
            current.append(character)
        }
        return result
    }

    /// The `file:line` of each spawn in `text` whose attributes argument, the fourth, is `nil`.
    static func offenders(in text: String, path: String) -> [String] {
        var found: [String] = []
        for match in text.matches(of: call) {
            let lineStart = text[..<match.range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            guard !text[lineStart...].trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
            let open = text.index(before: match.range.upperBound)
            let arguments = arguments(in: text, after: open)
            guard arguments.count > 3, arguments[3] == "nil" else { continue }
            let line = text[..<match.range.lowerBound].filter { $0 == "\n" }.count + 1
            found.append("\(path):\(line)")
        }
        return found
    }

    /// Every spawn in `Sources/` and `Tests/` passes attributes, so none can leave its parent's descriptors open in the child.
    ///
    /// Comment lines are skipped — naming the call is not making it.
    @Test func everySpawnPassesAttributes() throws {
        var bare: [String] = []
        for source in try Self.sources() {
            bare += Self.offenders(in: source.text, path: source.path)
        }

        #expect(bare.isEmpty, "pass attributes carrying the close-on-exec default, or spawn through the tests' isolated helper:\n\(bare.joined(separator: "\n"))")
    }

    /// The check itself finds a spawn with no attributes, on one line or several, and passes one with them.
    @Test func aSpawnWithNilAttributesIsFoundAndOneWithAttributesIsNot() {
        let bare = "var pid = pid_t()\nlet status = posix_spawn(&pid, path,\n    nil, nil, argv, envp)\n"
        let fine = "let status = posix_spawn(&pid, path, &actions, &attributes, argv, envp)\n"
        let comment = "    // posix_spawn(&pid, path, nil, nil, argv, envp)\n"

        #expect(Self.offenders(in: bare, path: "Gizmo.swift") == ["Gizmo.swift:2"])
        #expect(Self.offenders(in: fine, path: "Gizmo.swift").isEmpty)
        #expect(Self.offenders(in: comment, path: "Gizmo.swift").isEmpty)
    }
}
