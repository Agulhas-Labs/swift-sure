//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers that `affected` hands the narrowing the spellings its scan recorded, so a file that cannot write `Gizmo.line` is never read for it.
@Suite(.serialized, .temporaryDirectories)
struct AffectedSpellingsPassThroughTests {
    /// An engine over a fixture where `Gizmo.line` is changed and uncommitted, one suite writes `Gizmo.line`, and more files than a name may be write `line` only on other types.
    private static func engine() async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        var files = [
            "Package.swift": "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"Lib\",\n    targets: [\n        .target(name: \"Lib\"),\n        .testTarget(name: \"LibTests\", dependencies: [\"Lib\"]),\n    ]\n)\n",
            "Sources/Lib/Gizmo.swift": gizmo(returning: "count"),
            "Tests/LibTests/KettleTests.swift": "import Testing\n@testable import Lib\n\nstruct KettleTests {\n    @Test func runs() {\n        _ = Gizmo.line(count: 2)\n    }\n}\n",
        ]
        for index in 0 ... AffectedRenderer.nameEvidenceFileCap {
            files["Sources/Lib/Crowd\(index).swift"] = "public struct Pump\(index) {\n    public init() {}\n    public func line(count: Int) -> Int {\n        count\n    }\n}\n\npublic func crowd\(index)() -> Int {\n    Pump\(index)().line(count: \(index))\n}\n"
        }
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write(gizmo(returning: "count + 1"), to: "Sources/Lib/Gizmo.swift", in: root)
        return try SiftEngine(directory: root)
    }

    private static func gizmo(returning value: String) -> String {
        "public enum Gizmo {\n    public static func line(count: Int) -> String {\n        String(\(value))\n    }\n}\n"
    }

    /// The narrowing reads the file writing `Gizmo.line` and none whose recorded spellings rule it out.
    @Test
    func aFileWhoseRecordedSpellingsRuleItOutIsNotReadForTheOwnerQualifiedCheck() async throws {
        let engine = try await Self.engine()
        let log = ReadLog()

        let counting: @Sendable (String) -> Data? = { path in
            log.record(path)
            return FileManager.default.contents(atPath: path)
        }

        let output = try await OwnerQualifiedMentions.$reader.withValue(counting) {
            try await engine.affected(options: AffectedOptions(), freshness: engine.ensureFresh())
        }

        let read = log.paths

        #expect(output.contains("LibTests.KettleTests/runs() — 1 hop, name match"), "\(output)")
        #expect(read.contains { $0.hasSuffix("/Tests/LibTests/KettleTests.swift") }, "\(read)")
        #expect(!read.contains { $0.contains("/Sources/Lib/Crowd") }, "\(read.count) reads, among them \(read.prefix(3))")
    }
}

private extension AffectedSpellingsPassThroughTests {
    /// The paths a bound reader was asked for, safe to append to from any task.
    final class ReadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        var paths: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record(_ path: String) {
            lock.lock()
            storage.append(path)
            lock.unlock()
        }
    }
}
