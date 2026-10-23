//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A path target naming a file on disk in a folder no repository encloses is refused, never answered from another repository's copy.
@Suite(.temporaryDirectories)
struct UnindexedPathResolutionTests {
    private static var path: String {
        "Sources/Lib/Depot.swift"
    }

    private static func makeRegistry() throws -> RootsRegistry {
        try RootsRegistry(fileURL: TestSources.makeTempDirectory().appendingPathComponent("roots.json"))
    }

    /// An indexed repo declaring `Depot`, recorded in `registry`; at `location` when given.
    @discardableResult
    private static func makeIndexedRepo(in registry: RootsRegistry, at location: URL? = nil) async throws -> URL {
        let root = try location.map { try TestSources.makeTempRepo(at: $0) } ?? TestSources.makeTempRepo()
        try TestSources.write("public struct Depot { public let value: Int }", to: path, in: root)
        try TestSources.commitAll(in: root, message: "seed")
        try await SiftEngine(directory: root, registry: registry).ensureFresh()
        return root
    }

    /// A folder no repository encloses, optionally holding its own copy of the path.
    private static func makeArchive(holdingTheFile: Bool, sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let folder = try TestSources.makeTempDirectory().resolvingSymlinksInPath()
        #expect(try GitContext.enclosingRoot(from: folder) == nil, sourceLocation: sourceLocation)
        if holdingTheFile {
            try TestSources.write("public struct Depot { public let value: Int }", to: path, in: folder)
        }
        return folder
    }

    private static func refusal(
        directory: URL, registry: RootsRegistry, probing target: String, namedExplicitly: Bool = false, home: URL? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Refusal? {
        do {
            _ = try RootResolver.resolve(directory: directory, registry: registry, probing: target, namedExplicitly: namedExplicitly, home: home ?? URL(fileURLWithPath: "/nonexistent-home"))
        } catch let EngineError.fileInNoRepository(file, origin, remedyFolder, indexedCopies) {
            return Refusal(file: file, origin: origin, remedyFolder: remedyFolder, indexedCopies: indexedCopies)
        } catch {
            Issue.record("refused with another error: \(error)", sourceLocation: sourceLocation)
        }
        return nil
    }

    @Test
    func aFileOnDiskInNoRepositoryIsRefusedRatherThanAnsweredFromAnIndexedCopy() async throws {
        let registry = try Self.makeRegistry()
        let indexed = try await Self.makeIndexedRepo(in: registry)
        let archive = try Self.makeArchive(holdingTheFile: true)

        let refused = try #require(Self.refusal(directory: archive, registry: registry, probing: Self.path))

        #expect(refused.file == archive.appendingPathComponent(Self.path).path)
        #expect(refused.origin == archive.path)
        #expect(refused.remedyFolder == archive.path)
        #expect(refused.indexedCopies.map { URL(fileURLWithPath: $0).standardizedFileURL } == [indexed.standardizedFileURL])
        let message = String(describing: EngineError.fileInNoRepository(file: refused.file, origin: refused.origin, remedyFolder: refused.remedyFolder, indexedCopies: refused.indexedCopies))
        #expect(message.hasPrefix("\(refused.file) is in no git repository, so swift-sure has no index of it"))
        #expect(message.contains("run git init and commit in \(archive.path)."))
        #expect(message.hasSuffix("pass root: (CLI: --root) with one of:\n  \(refused.indexedCopies[0])"))
    }

    @Test
    func aSessionRootedAtTheHomeFolderIsToldToInitTheFilesOwnFolderNotHome() async throws {
        let registry = try Self.makeRegistry()
        try await Self.makeIndexedRepo(in: registry)
        let archive = try Self.makeArchive(holdingTheFile: true)
        let own = archive.appendingPathComponent("Sources/Lib").path

        let refused = try #require(Self.refusal(directory: archive, registry: registry, probing: Self.path, home: archive))

        #expect(refused.origin == archive.path)
        #expect(refused.remedyFolder == own)
        let message = String(describing: EngineError.fileInNoRepository(file: refused.file, origin: refused.origin, remedyFolder: refused.remedyFolder, indexedCopies: []))
        #expect(message.contains("run git init and commit in \(own)."))
    }

    @Test
    func aPathNotOnDiskStillAdoptsTheOnlyIndexedRepositoryRecordingIt() async throws {
        let registry = try Self.makeRegistry()
        let indexed = try await Self.makeIndexedRepo(in: registry)
        let archive = try Self.makeArchive(holdingTheFile: false)

        let resolved = try RootResolver.resolve(directory: archive, registry: registry, probing: Self.path)

        #expect(resolved.url.standardizedFileURL == indexed.standardizedFileURL)
    }

    @Test
    func aSymbolNameStillAdoptsEvenWhereTheArchiveHoldsTheFile() async throws {
        let registry = try Self.makeRegistry()
        let indexed = try await Self.makeIndexedRepo(in: registry)
        let archive = try Self.makeArchive(holdingTheFile: true)

        let resolved = try RootResolver.resolve(directory: archive, registry: registry, probing: "Depot")

        #expect(resolved.url.standardizedFileURL == indexed.standardizedFileURL)
    }

    @Test
    func aFileInsideAnotherRepositoryUnderTheContainerIsNotRefused() async throws {
        let registry = try Self.makeRegistry()
        let container = try Self.makeArchive(holdingTheFile: false)
        let indexed = try await Self.makeIndexedRepo(in: registry, at: container.appendingPathComponent("app"))

        let resolved = try RootResolver.resolve(directory: container, registry: registry, probing: "app/" + Self.path)

        #expect(resolved.url.standardizedFileURL == indexed.standardizedFileURL)
    }

    @Test
    func anAbsolutePathToTheFileOnDiskIsRefusedTheSameWay() async throws {
        let registry = try Self.makeRegistry()
        try await Self.makeIndexedRepo(in: registry)
        let archive = try Self.makeArchive(holdingTheFile: true)
        let elsewhere = try Self.makeArchive(holdingTheFile: false)
        let absolute = archive.appendingPathComponent(Self.path).path

        let refused = try #require(Self.refusal(directory: elsewhere, registry: registry, probing: absolute))

        #expect(refused.file == absolute)
        #expect(refused.origin == elsewhere.path)
        #expect(refused.remedyFolder == archive.appendingPathComponent("Sources/Lib").path)
        // No index records an absolute path, so no copy is offered; the remedy is still given.
        #expect(refused.indexedCopies.isEmpty)
        let message = String(describing: EngineError.fileInNoRepository(file: refused.file, origin: refused.origin, remedyFolder: refused.remedyFolder, indexedCopies: refused.indexedCopies))
        #expect(message.contains("run git init and commit in \(archive.appendingPathComponent("Sources/Lib").path)."))
        #expect(!message.contains(elsewhere.path))
    }

    @Test
    func aNamedFolderHoldingTheFileAndAnIndexedRepositoryRefusesWithTheNewError() async throws {
        let registry = try Self.makeRegistry()
        let container = try Self.makeArchive(holdingTheFile: true)
        let indexed = try await Self.makeIndexedRepo(in: registry, at: container.appendingPathComponent("app"))

        let refused = try #require(Self.refusal(directory: container, registry: registry, probing: Self.path, namedExplicitly: true))

        #expect(refused.file == container.appendingPathComponent(Self.path).path)
        #expect(refused.indexedCopies.map { URL(fileURLWithPath: $0).standardizedFileURL } == [indexed.standardizedFileURL])
    }
}

extension UnindexedPathResolutionTests {
    private struct Refusal {
        let file: String
        let origin: String
        let remedyFolder: String
        let indexedCopies: [String]
    }
}
