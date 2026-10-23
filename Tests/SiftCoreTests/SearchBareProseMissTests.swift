//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A search of bare words only that matches nothing points at `strings` and `where`; any other miss, and any hit, carries no such line.
@Suite(.temporaryDirectories)
struct SearchBareProseMissTests {
    private static var source: String {
        """
        struct Widget {
            var label: String { "Widget" }
        }
        struct Depot {}
        """
    }

    private func searched(_ query: String, count: Bool = false) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.source, to: "Sources/App/Widget.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        return try await SiftEngine(directory: root).search(query: query, count: count)
    }

    @Test
    func aBareOnlyMissQuotesTheSentTextInTheRedirect() async throws {
        let answer = try await searched("gizmo score high")

        #expect(answer.contains("no declarations match"), "\(answer)")
        #expect(answer.contains("each bare word was read as name: and ANDed — for display text ask strings \"gizmo score high\"; for one declaration, where <Name>"), "\(answer)")
    }

    @Test(arguments: ["\"gizmo score\"", "'gizmo score'"])
    func aQuotedQueryIsNotQuotedTwiceInTheRedirect(query: String) async throws {
        let answer = try await searched(query)

        #expect(answer.contains("ask strings \"gizmo score\"; for one declaration"), "\(answer)")
    }

    @Test
    func anInnerQuoteIsEscapedInTheRedirect() async throws {
        let answer = try await searched("gizmo\"score")

        #expect(answer.contains("ask strings \"gizmo\\\"score\"; for one declaration"), "\(answer)")
    }

    @Test
    func aMissWithAFieldTermCarriesNoRedirect() async throws {
        let answer = try await searched("kind:struct gizmo")

        #expect(answer.contains("no declarations match"), "\(answer)")
        #expect(!answer.contains("each bare word was read"), "\(answer)")
    }

    @Test
    func aBareOnlyHitCarriesNoRedirect() async throws {
        let answer = try await searched("widget")

        #expect(!answer.contains("no declarations match"), "\(answer)")
        #expect(!answer.contains("each bare word was read"), "\(answer)")
    }

    @Test
    func negatedBareWordsAloneCountAsBareOnly() async throws {
        let answer = try await searched("!widget !label !depot")

        #expect(answer.contains("no declarations match"), "\(answer)")
        #expect(answer.contains("ask strings \"!widget !label !depot\""), "\(answer)")
    }

    @Test
    func theRedirectNamesTheOriginalWordsNotTheNameRewriting() async throws {
        let answer = try await searched("gizmo score")
        let line = try #require(answer.split(separator: "\n").first { $0.hasPrefix("each bare word") })

        #expect(line.contains("strings \"gizmo score\""), "\(line)")
        #expect(!line.contains("strings \"name:"), "\(line)")
    }

    @Test
    func aCountMissCarriesTheRedirectToo() async throws {
        let answer = try await searched("gizmo score", count: true)

        #expect(answer.contains("ask strings \"gizmo score\""), "\(answer)")
    }
}
