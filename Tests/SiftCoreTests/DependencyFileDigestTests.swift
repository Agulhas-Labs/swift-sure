//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `digest` of a file inside a resolved package's checkout: parsed on demand and answered unindexed, while every other hidden path keeps its refusal.
@Suite(.temporaryDirectories)
struct DependencyFileDigestTests {
    private static var checkoutFile: String {
        ".build/checkouts/DepotKit/Sources/DepotKit/Depot.swift"
    }

    private static var source: String {
        "public struct DepotBox {\n    public func seal() {}\n}\n\npublic struct DepotStore {}\n"
    }

    private static var resolvedV3: String {
        """
        {"pins":[{"identity":"depotkit","kind":"remoteSourceControl","location":"https://example.com/acme/DepotKit.git","state":{"revision":"abc","version":"2.4.1"}}],"version":3}
        """
    }

    private static var resolvedV1: String {
        """
        {"object":{"pins":[{"package":"DepotKit","repositoryURL":"https://example.com/acme/DepotKit.git","state":{"branch":null,"revision":"abc","version":"1.9.0"}}]},"version":1}
        """
    }

    private static func engine(resolved: String? = resolvedV3, checkoutFile: String = checkoutFile) async throws -> (SiftEngine, URL) {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Anchor {}\n", to: "Sources/App/Anchor.swift", in: root)
        try TestSources.write("struct DepotBox {}\n", to: "Sources/App/Crate.swift", in: root)
        try TestSources.write(source, to: checkoutFile, in: root)
        try TestSources.write("struct Rule {}\n", to: ".tooling/Lint/Rule.swift", in: root)
        if let resolved {
            try TestSources.write(resolved, to: "Package.resolved", in: root)
        }
        try TestSources.commitAll(in: root, message: "seed")
        let engine = try SiftEngine(directory: root)
        _ = try await engine.ensureFresh()
        return (engine, root)
    }

    @Test
    func aCheckoutFileIsDigestedWithTheDependencyMarkerAndVersion() async throws {
        let (engine, _) = try await Self.engine()

        let answer = try engine.digest(target: Self.checkoutFile, options: DigestOptions())

        #expect(answer.contains("\(Self.checkoutFile) (dependency DepotKit 2.4.1) — read on demand, not indexed"))
        #expect(answer.contains("DepotBox"))
        #expect(answer.contains("DepotStore"))
        #expect(!answer.contains("exists but is not indexed"))
    }

    /// The module line names the target an `import` spells, `Sources/<Target>/`, not the checkout's directory.
    @Test
    func theModuleIsTheTargetDirectoryNotThePackage() async throws {
        let file = ".build/checkouts/depot-kit/Sources/DepotStore/Depot.swift"
        let (engine, _) = try await Self.engine(checkoutFile: file)

        let answer = try engine.digest(target: file, options: DigestOptions())

        #expect(answer.contains("\(file) — module: DepotStore"), "\(answer)")
        #expect(!answer.contains("module: depot-kit"), "\(answer)")
    }

    @Test
    func theOlderResolvedFormatNamesTheVersionToo() async throws {
        let (engine, _) = try await Self.engine(resolved: Self.resolvedV1)

        let answer = try engine.digest(target: Self.checkoutFile, options: DigestOptions())

        #expect(answer.contains("(dependency DepotKit 1.9.0)"))
    }

    @Test
    func anUnreadableVersionKeepsTheMarkerWithoutOne() async throws {
        let (engine, _) = try await Self.engine(resolved: nil)

        let answer = try engine.digest(target: Self.checkoutFile, options: DigestOptions())

        #expect(answer.contains("\(Self.checkoutFile) (dependency DepotKit) — read on demand, not indexed"))
    }

    @Test
    func aLineRangeInsideACheckoutFileAnswersTheDeclarationItSpans() async throws {
        let (engine, _) = try await Self.engine()

        let answer = try engine.digest(target: "\(Self.checkoutFile):1-3", options: DigestOptions())

        #expect(answer.contains("(dependency DepotKit 2.4.1)"))
        #expect(answer.contains("public func seal() {}"))
        #expect(!answer.contains("exists but is not indexed"))
    }

    @Test
    func aSourcePackagesCheckoutIsRead() async throws {
        let file = "SourcePackages/checkouts/DepotKit/Sources/Depot.swift"
        let (engine, _) = try await Self.engine(checkoutFile: file)

        let answer = try engine.digest(target: file, options: DigestOptions())

        #expect(answer.contains("\(file) (dependency DepotKit 2.4.1)"))
        #expect(answer.contains("DepotStore"))
    }

    @Test
    func aPathLeavingTheCheckoutByDotsKeepsTheRefusal() async throws {
        let (engine, _) = try await Self.engine()

        let answer = try engine.digest(target: ".build/checkouts/DepotKit/../../../.tooling/Lint/Rule.swift", options: DigestOptions())

        #expect(answer == ".tooling/Lint/Rule.swift exists but is not indexed — .tooling is hidden, and a hidden path is never indexed. A plain Read is the way to see it: nothing in it is in the index.")
    }

    @Test
    func aLinkLeavingTheCheckoutKeepsTheRefusal() async throws {
        let (engine, root) = try await Self.engine()
        let link = root.appendingPathComponent(".build/checkouts/DepotKit/Sources/Escape.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent(".tooling/Lint/Rule.swift"))

        let answer = try engine.digest(target: ".build/checkouts/DepotKit/Sources/Escape.swift", options: DigestOptions())

        #expect(answer.hasPrefix(".build/checkouts/DepotKit/Sources/Escape.swift exists but is not indexed — .build is hidden, and a hidden path is never indexed."))
        #expect(!answer.contains("dependency"))
    }

    @Test
    func aHiddenPathOutsideACheckoutKeepsTheRefusal() async throws {
        let (engine, _) = try await Self.engine()

        let answer = try engine.digest(target: ".tooling/Lint/Rule.swift", options: DigestOptions())

        #expect(answer == ".tooling/Lint/Rule.swift exists but is not indexed — .tooling is hidden, and a hidden path is never indexed. A plain Read is the way to see it: nothing in it is in the index.")
    }

    @Test
    func aDirectoryOrANonSwiftFileInACheckoutKeepsTheRefusal() async throws {
        let (engine, root) = try await Self.engine()
        try TestSources.write("notes\n", to: ".build/checkouts/DepotKit/README.txt", in: root)

        let directory = try engine.digest(target: ".build/checkouts/DepotKit/Sources/DepotKit/", options: DigestOptions())
        let text = try engine.digest(target: ".build/checkouts/DepotKit/README.txt", options: DigestOptions())

        #expect(!directory.contains("dependency"))
        #expect(!text.contains("dependency"))
    }

    @Test
    func theDependencysDeclarationsAreNeverIndexed() async throws {
        let (engine, _) = try await Self.engine()
        _ = try engine.digest(target: Self.checkoutFile, options: DigestOptions())

        let found = try await engine.lookup(symbol: "DepotStore", freshness: engine.ensureFresh())
        let same = try await engine.lookup(symbol: "DepotBox", freshness: engine.ensureFresh())

        #expect(!found.contains("Depot.swift"))
        #expect(!same.contains("checkouts"))
    }
}
