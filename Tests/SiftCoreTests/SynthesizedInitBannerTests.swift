//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers the banners on a `Type.init(labels…)` target served from the lone synthesized memberwise initializer: the parse-error and guessed-module banners a plain `Type.init` carries.
@Suite(.temporaryDirectories)
struct SynthesizedInitBannerTests {
    private static func engine(source: String) async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(source, to: "Sources/Core/Gizmo.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return engine
    }

    @Test
    func aLoneSynthesizedInitializerInABrokenFileCarriesTheParseErrorBanner() async throws {
        let engine = try await Self.engine(source: """
        struct Gizmo {
            var a: Int
            var b: Int
        }

        func broken( {
        """)

        let answer = try engine.digest(target: "Gizmo.init(a:)", options: DigestOptions())

        #expect(answer.contains("⚠ parse errors"))
        #expect(answer.contains("resolved init(a:) to init(a:b:)"))
    }

    @Test
    func aLoneSynthesizedInitializerInAGuessedModuleCarriesTheGuessedModuleBanner() async throws {
        let engine = try await Self.engine(source: """
        struct Gizmo {
            var a: Int
            var b: Int
        }
        """)

        let answer = try engine.digest(target: "Gizmo.init(a:)", options: DigestOptions())

        #expect(answer.contains("⚠ module guessed"))
        #expect(answer.contains("resolved init(a:) to init(a:b:)"))
    }
}
