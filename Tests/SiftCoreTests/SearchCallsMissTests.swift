//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A search whose `calls:` term emptied the answer says when the same name is used, so `uses:` is the term to try.
@Suite(.temporaryDirectories)
struct SearchCallsMissTests {
    private static var source: String {
        """
        struct Widget {
            func load() -> Int { Gizmo.shared.placeholderCount }
            func store() -> Int { Gizmo.shared.placeholderCount + 1 }
            var label: String { "Widget" }
        }
        """
    }

    private func searched(_ query: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(Self.source, to: "Sources/App/Widget.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        return try await SiftEngine(directory: root).search(query: query)
    }

    @Test
    func aCallsMissForAUsedPropertyNamesTheUsesQueryAndItsCount() async throws {
        let answer = try await searched("calls:placeholderCount")

        #expect(answer.contains("placeholderCount is used, not called, in 3 declarations: try uses:placeholderCount"), "\(answer)")
    }

    @Test
    func aNameUsesDoesNotMatchEitherCarriesNoLine() async throws {
        let answer = try await searched("calls:executionCount")

        #expect(answer.contains("no declarations match"), "\(answer)")
        #expect(!answer.contains("is used, not called"), "\(answer)")
    }

    @Test
    func aNegatedCallsTermCarriesNoLine() async throws {
        let answer = try await searched("kind:func !calls:placeholderCount")

        #expect(!answer.contains("is used, not called"), "\(answer)")
    }

    @Test
    func aMissAnotherTermCausedCarriesNoLine() async throws {
        let answer = try await searched("kind:actor calls:placeholderCount")

        #expect(answer.contains("kind:actor removed"), "\(answer)")
        #expect(!answer.contains("is used, not called"), "\(answer)")
    }

    @Test
    func theOtherTermsAreKeptInTheUsesScan() async throws {
        let answer = try await searched("name:load calls:placeholderCount")

        #expect(answer.contains("placeholderCount is used, not called, in 1 declaration: try uses:placeholderCount"), "\(answer)")
    }
}
