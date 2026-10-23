//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers which files the scan for a name's uses as a type parses: only those writing the name as a whole word, never one holding it only inside a longer name.
@Suite(.temporaryDirectories)
struct TypeUseScanTests {
    /// The paths whose source a scan for `Gizmo` that nothing settles hands to the parse.
    private static func parsedPaths(_ files: [String: String], sourceLocation: SourceLocation = #_sourceLocation) throws -> Set<String> {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        let parsed = ParsedPaths()
        var scan = TypeUseScan(repoRoot: root, enumerator: FileEnumerator(repoRoot: root, config: SiftConfig(), gitListing: { files.keys.sorted() }))
        let parse = scan.sitesInSource
        scan.sitesInSource = { source, path, name in
            parsed.insert(path)
            return parse(source, path, name)
        }
        let settled = try scan.settles("Gizmo") { _ in false }
        #expect(!settled, sourceLocation: sourceLocation)
        return parsed.paths
    }

    /// A file holding the name only inside longer names is never parsed; one writing it as a word is, a comment's word included.
    @Test
    func onlyFilesWritingTheNameAsAWordAreParsed() throws {
        let parsed = try Self.parsedPaths([
            "Sources/GizmoCore/Reading.swift": "func read(_ gizmo: Gizmo) -> Int {\n    0\n}\n",
            "Sources/GizmoCore/Note.swift": "// The Gizmo a reading comes from.\nlet unit = 1\n",
            "Sources/GizmoCore/Dial.swift": "struct GizmoKit {\n    var needle: SubGizmo?\n    var gizmo_scale = 1\n}\n",
            "Sources/GizmoCore/Plain.swift": "struct Plain {}\n",
        ])

        #expect(parsed == ["Sources/GizmoCore/Reading.swift", "Sources/GizmoCore/Note.swift"])
    }
}

private extension TypeUseScanTests {
    /// The paths a scan parsed, recorded from the threads it parses on.
    final class ParsedPaths: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: Set<String> = []

        var paths: Set<String> {
            lock.withLock { recorded }
        }

        func insert(_ path: String) {
            lock.withLock { _ = recorded.insert(path) }
        }
    }
}
