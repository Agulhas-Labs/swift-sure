//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how the stale-project note reads brace groups in excludes, escaped pbxproj values and template bundles.
struct XcodeGenStaleProjectGlobTests {
    @Test
    func `a brace group in an exclude matches each alternative`() throws {
        let spec = Self.spec(source: "        excludes: [\"**/*.{mock,stub}.swift\"]\n")
        let line = try Self.note(spec: spec, files: ["Sources/a.mock.swift", "Sources/Deep/b.stub.swift", "Sources/c.swift"], listed: [])

        #expect(line?.contains("(c.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    @Test
    func `a brace group with no comma is its one alternative`() throws {
        let line = try Self.note(spec: Self.spec(source: "        excludes: [\"{Gizmos}\"]\n"), files: ["Sources/Gizmos/a.swift", "Sources/c.swift"], listed: [])

        #expect(line?.contains("(c.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    @Test
    func `an empty brace group vanishes from the pattern`() throws {
        let line = try Self.note(spec: Self.spec(source: "        excludes: [\"a{}bc.swift\"]\n"), files: ["Sources/abc.swift", "Sources/c.swift"], listed: [])

        #expect(line?.contains("(c.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    @Test
    func `each alternative of a brace group ending in a slash names a directory`() throws {
        let spec = Self.spec(source: "        excludes: [\"{Mocks/,Stubs/}\"]\n")
        let line = try Self.note(spec: spec, files: ["Sources/Mocks/a.swift", "Sources/Stubs/b.swift", "Sources/c.swift"], listed: [])

        #expect(line?.contains("(c.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    @Test
    func `nested brace groups expand and a group stays apart from its neighbours`() throws {
        let spec = Self.spec(source: "        excludes: [\"{a,{b,c}}.swift\", \"{a.c,b}x.swift\"]\n")
        let line = try Self.note(spec: spec, files: ["Sources/a.swift", "Sources/c.swift", "Sources/a.cx.swift", "Sources/abx.swift"], listed: [])

        #expect(line?.contains("(abx.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    @Test
    func `a quoted pbxproj value with an escaped quote names the file on disk`() throws {
        let line = try Self.note(spec: Self.spec(source: ""), files: ["Sources/Say\"Hi.swift"], listed: ["\"Say\\\"Hi.swift\""])

        #expect(line == nil)
    }

    @Test
    func `a Swift file inside a template directory is a source of its own`() throws {
        // A regression guard: XcodeGen makes a group of a template directory and compiles its files, and this held before the brace work too.
        let line = try Self.note(spec: Self.spec(source: ""), files: ["Sources/Gizmo.xctemplate/Gizmo.swift", "Sources/A.swift"], listed: ["A.swift"])

        #expect(line?.contains("(Gizmo.swift)") == true)
        #expect(line?.contains("1 Swift file") == true)
    }

    /// Builds a fixture holding exactly `files` (paths below the root) and a project whose pbxproj holds `listed` as written, and returns the note for it.
    private static func note(spec: String, files: [String], listed: [String]) throws -> String? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stale-project-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        for file in files {
            let url = root.appendingPathComponent(file)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "struct S {}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        try spec.write(to: root.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        try listed.map { "path = \($0);" }.joined(separator: "\n").write(to: root.appendingPathComponent("App.xcodeproj/project.pbxproj"), atomically: true, encoding: .utf8)
        return XcodeGenStaleProject.line(project: root.appendingPathComponent("App.xcodeproj"), repositoryRoot: root)
    }

    /// A spec whose one source is `Sources`, with `source` the extra keys of that entry.
    private static func spec(source: String) -> String {
        "name: App\ntargets:\n  App:\n    type: application\n    platform: iOS\n    sources:\n      - path: Sources\n\(source)"
    }
}
