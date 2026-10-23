//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A qualified member query asked with no store counts a site written inside a type declared in a function under its own reason, since that type's supertypes and members are not shown.
@Suite(.temporaryDirectories)
struct WhereLocalScopeReasonTests {
    private static func line(_ source: String) async throws -> (line: String?, output: String) {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(source, to: "Sources/App/Uses.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let output = try await CallSiteHeadingTests.lookup("Depot.load", in: root)
        let line = output.split(separator: "\n").first { $0.hasPrefix("\"load\" (") }.map(String.init)
        return (line, output)
    }

    /// A site inside a struct declared in a function is kept and counted as on a name a type declared in a function may supply.
    @Test
    func aSiteInATypeDeclaredInAFunctionIsCountedAsLocalScope() async throws {
        let (found, output) = try await Self.line("struct Depot {\n    static func load(_ count: Int) {}\n}\nenum Spare {\n    static func load(_ count: Int) {}\n}\nfunc probe() {\n    struct Orchard {\n        func uses() {\n            Spare.load(1)\n        }\n    }\n}\n")

        #expect(output.contains("Spare.load(1)"), "\(output)")
        let line = try #require(found, "\(output)")
        #expect(line.contains("1 on names a type declared in a function may supply (Spare ×1)"), "\(line)")
    }

    /// The same site in a struct declared at the top level is no local scope, so Spare is another type there and the site is set apart, with no such clause.
    @Test
    func aSiteInATopLevelTypeIsNotCountedAsLocalScope() async throws {
        let (line, output) = try await Self.line("struct Depot {\n    static func load(_ count: Int) {}\n}\nenum Spare {\n    static func load(_ count: Int) {}\n}\nstruct Orchard {\n    func uses() {\n        Spare.load(1)\n    }\n}\n")

        #expect(!output.contains("Spare.load(1)"), "\(output)")
        #expect(line == nil, "\(output)")
        #expect(output.contains("on other types dropped"), "\(output)")
        #expect(!output.contains("a type declared in a function"), "\(output)")
    }
}
