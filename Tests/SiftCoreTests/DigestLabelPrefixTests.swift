//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers a `Type.member(labels…)` target whose labels are the first labels of a longer member: one such member is served under a `resolved` line, several are listed alone, and a different order or an exact match is untouched.
@Suite(.temporaryDirectories)
struct DigestLabelPrefixTests {
    private static var source: String {
        """
        struct Writer {
            init(opening root: String, cache: Int, clock: Int) {
                _ = "single-init-body"
            }

            init(cache: Int, opening root: String) {
                _ = "reordered-init-body"
            }

            func save(_ item: Int, to path: String) {
                _ = "save-short-body"
            }

            func save(_ item: Int, to path: String, force: Bool) {
                _ = "save-short-body"
            }

            func exact(one: Int) {
                _ = "exact-short"
            }

            func exact(one: Int, two: Int) {
                _ = "exact-long"
            }
        }

        struct Plain {
            var a: Int
            var b: Int
        }

        extension Plain {
            init(a: Int, c: Int) {
                self.init(a: a, b: c)
            }
        }

        extension Writer {
            func flush(into sink: Int, now: Bool) {
                _ = "flush-body"
            }
        }
        """
    }

    private static func engine() async throws -> SiftEngine {
        let root = try TestSources.makeTempRepo()
        try TestSources.write(source, to: "Sources/Core/Writer.swift", in: root)
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return engine
    }

    @Test
    func oneMemberBeginningWithTheLabelsIsServedUnderAResolvedLine() async throws {
        let engine = try await Self.engine()

        let answer = try engine.digest(target: "Writer.init(opening:)", options: DigestOptions())

        let first = answer.split(separator: "\n").first.map(String.init)

        #expect(first == "resolved init(opening:) to init(opening:cache:clock:) (the only init on Writer whose labels begin opening:)")
        #expect(answer.contains("single-init-body"))
        #expect(!answer.contains("reordered-init-body"))
        #expect(!answer.contains("nearest symbols"))
    }

    @Test
    func severalMembersBeginningWithTheLabelsAreListedAlone() async throws {
        let engine = try await Self.engine()

        let answer = try engine.digest(target: "Writer.save(_:)", options: DigestOptions())

        #expect(answer.contains("no member named save(_:) on Writer; 2 begin with those labels:"))
        let listed = answer.split(separator: "\n").filter { $0.hasPrefix("  ") }
        #expect(listed.count == 2)
        #expect(listed.contains { $0.contains("save(_:to:)") })
        #expect(listed.contains { $0.contains("save(_:to:force:)") })
        #expect(!answer.contains("nearest symbols"))
        #expect(!answer.contains("save-short-body"))
    }

    @Test
    func labelsInAnotherOrderDoNotMatch() async throws {
        let engine = try await Self.engine()

        let answer = try engine.digest(target: "Writer.init(clock:)", options: DigestOptions())

        #expect(!answer.contains("resolved"))
        #expect(!answer.contains("begin with those labels"))
        #expect(answer.contains("nearest symbols"))
    }

    @Test
    func anExactMatchPrintsNoResolvedLine() async throws {
        let engine = try await Self.engine()

        let answer = try engine.digest(target: "Writer.exact(one:)", options: DigestOptions())

        #expect(!answer.contains("resolved"))
        #expect(answer.contains("exact-short"))
        #expect(!answer.contains("exact-long"))
    }

    @Test
    func aMemberDeclaredInAnExtensionIsFound() async throws {
        let engine = try await Self.engine()

        let answer = try engine.digest(target: "Writer.flush(into:)", options: DigestOptions())

        #expect(answer.hasPrefix("resolved flush(into:) to flush(into:now:) (the only flush on Writer whose labels begin into:)"))
        #expect(answer.contains("flush-body"))
    }

    @Test
    func emptyLabelsAreNotAPrefixOfEverything() async throws {
        let engine = try await Self.engine()

        for target in ["Writer.init()", "Writer.only()", "Writer.save()"] {
            let answer = try engine.digest(target: target, options: DigestOptions())

            #expect(!answer.contains("resolved"))
            #expect(!answer.contains("begin with those labels"))
        }
    }

    @Test
    func theSeveralMatchRefusalIsAMissAndTheSingleResolutionIsAHit() async throws {
        let engine = try await Self.engine()

        let several = try engine.measuredDigest(target: "Writer.save(_:)", options: DigestOptions())
        let single = try engine.measuredDigest(target: "Writer.init(opening:)", options: DigestOptions())

        #expect(several.missed)
        #expect(!single.missed)
    }

    @Test
    func aSynthesizedMemberwiseInitializerCountsAsACandidate() async throws {
        let engine = try await Self.engine()

        let answer = try engine.measuredDigest(target: "Plain.init(a:)", options: DigestOptions())

        #expect(answer.text.contains("no member named init(a:) on Plain; 2 begin with those labels:"))
        #expect(answer.text.contains("  init(a:b:) — synthesized initializer"))
        #expect(answer.text.contains("  init(a:c:) — init"))
        #expect(!answer.text.contains("resolved"))
        #expect(answer.missed)
    }
}
