//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A memberwise parameter is judged by the type of its own property, not of an earlier one in the same declaration.
@Suite(.temporaryDirectories)
struct WhereMemberwiseBindingTests {
    static var declarations: String {
        """
        struct Widget {
            var tags: [String], action: () -> Void
        }

        enum Other {
            struct Widget {
                init(tags: [String], _ action: () -> Void) {}
            }
        }
        """
    }

    static var calls: String {
        """
        enum Calls {
            static func build() {
                _ = Widget(tags: []) { }
            }
        }
        """
    }

    static func lookup(_ symbol: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(declarations, to: "Sources/App/Types.swift", in: root)
        try TestSources.write(calls, to: "Sources/App/Calls.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        let engine = try SiftEngine(directory: root)
        let freshness = try await engine.ensureFresh()
        return try await engine.lookup(symbol: symbol, freshness: freshness)
    }

    /// A trailing closure fits the memberwise initializer of a property declared after another of a non-closure type in one declaration, so the site is not given to the same-named type.
    @Test
    func aTrailingClosureFitsAPropertyDeclaredAfterAnotherInOneDeclaration() async throws {
        let output = try await Self.lookup("Widget.init")
        let sites = WhereAnswerRepetitionTests.sitesOnePerLine(output)

        #expect(sites.contains("Sources/App/Calls.swift:3  in Calls.build()"), "\(output)")
        #expect(!output.contains("labels fit"), "\(output)")
    }
}
