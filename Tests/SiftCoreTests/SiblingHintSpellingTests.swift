//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// The cross-root retry hint is spelled for the face that asked: `--root <path>` on the CLI, `root=<path>` in a tool call.
@Suite(.temporaryDirectories)
struct SiblingHintSpellingTests {
    private static func makeSiblings() async throws -> Siblings {
        let registry = try RootsRegistry(fileURL: TestSources.makeTempDirectory().appendingPathComponent("roots.json"))
        let declaring = try TestSources.makeTempRepo()
        try TestSources.write("public struct Depot {}\n", to: "Sources/Lib/Depot.swift", in: declaring)
        try TestSources.commitAll(in: declaring, message: "depot")
        _ = try await SiftEngine(directory: declaring, registry: registry).ensureFresh()

        let local = try TestSources.makeTempRepo()
        try TestSources.write("struct Local {}\n", to: "Sources/App/Local.swift", in: local)
        try TestSources.commitAll(in: local, message: "local")
        let engine = try SiftEngine(directory: local, registry: registry)
        _ = try await engine.ensureFresh()
        return Siblings(planless: engine, declaringRoot: declaring)
    }

    private static func lookups(_ siblings: Siblings, spelling: CallSpelling) async throws -> [String] {
        let freshness = try await siblings.planless.ensureFresh()
        let whereOutput = try await siblings.planless.lookup(symbol: "Depot", freshness: freshness, options: WhereOptions(includeSemantic: false, spelling: spelling))
        let digestOutput = try siblings.planless.digest(target: "Depot", options: DigestOptions(spelling: spelling))
        return [whereOutput, digestOutput]
    }

    @Test
    func theCommandLineHintNamesTheRootOption() async throws {
        let siblings = try await Self.makeSiblings()
        for output in try await Self.lookups(siblings, spelling: .commandLine) {
            #expect(output.contains("retry with --root \(siblings.declaringRoot.path)"), "\(output)")
            #expect(!output.contains("retry with root="), "\(output)")
        }
    }

    @Test
    func theToolCallHintIsTheOldRootArgument() async throws {
        let siblings = try await Self.makeSiblings()
        for output in try await Self.lookups(siblings, spelling: .toolCall) {
            #expect(output.contains("retry with root=\(siblings.declaringRoot.path)"), "\(output)")
            #expect(!output.contains("--root"), "\(output)")
        }
    }

    @Test
    func aCommandLinePathNeedingQuotesIsQuoted() {
        let pointer = SiblingPointer(root: "/tmp/my repo", declares: true)

        #expect(pointer.line(for: "Depot", spelling: .commandLine).hasSuffix("retry with --root '/tmp/my repo'"))
        #expect(pointer.line(for: "Depot", spelling: .toolCall).hasSuffix("retry with root=/tmp/my repo"))
    }
}

extension SiblingHintSpellingTests {
    private struct Siblings {
        let planless: SiftEngine
        let declaringRoot: URL
    }
}
