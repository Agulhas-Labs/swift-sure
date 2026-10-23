//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A fixture's `swift build` starts from the SDK stat cache an earlier fixture in the process computed rather than computing a 15 MB one of its own, and a native build is not given a `.build/out` to hold one.
@Suite(.temporaryDirectories, .serialized)
struct FixtureStatCacheSeedTests {
    /// A package of one empty target, in a directory of the test's scope.
    private static func makePackage() throws -> URL {
        let root = try TemporaryDirectory.make("stat-cache-package")
        try TestSources.write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "Gizmo", targets: [.target(name: "Gizmo")])
            """,
            to: "Package.swift",
            in: root
        )
        try TestSources.write("public struct Gizmo {}\n", to: "Sources/Gizmo/Gizmo.swift", in: root)
        return root
    }

    private static func build(_ root: URL, arguments: [String] = [], seed: URL) throws {
        try TestSources.swiftBuild(
            packageAt: root,
            includingTests: false,
            arguments: arguments,
            swiftPMTemporary: TemporaryDirectory.make("swiftpm"),
            statCacheSeed: seed
        )
    }

    @Test("A cache in the seed is in the fixture before its build runs, and still there after it")
    func seededCacheReachesTheFixture() throws {
        let seed = try TemporaryDirectory.make("stat-cache-seed")
        // Named for no SDK, so the build never finds it and never touches it: only the seeding can have put it in the fixture.
        let planted = seed.appendingPathComponent("planted-by-the-test.sdkstatcache")
        try Data("seed".utf8).write(to: planted)
        let root = try Self.makePackage()
        try Self.build(root, seed: seed)
        let arrived = root.appendingPathComponent(TestSources.statCacheDirectory).appendingPathComponent(planted.lastPathComponent)

        #expect(try String(contentsOf: arrived, encoding: .utf8) == "seed")
    }

    @Test("A native build is not given a .build/out")
    func nativeBuildGetsNoOut() throws {
        let seed = try TemporaryDirectory.make("stat-cache-seed")
        try Data("seed".utf8).write(to: seed.appendingPathComponent("planted-by-the-test.sdkstatcache"))
        let root = try Self.makePackage()
        try Self.build(root, arguments: ["--build-system", "native"], seed: seed)

        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/out").path))
    }

    @Test("The first Swift Build fixture leaves its cache in an empty seed")
    func firstBuildFillsTheSeed() throws {
        let seed = try TemporaryDirectory.make("stat-cache-seed")
        try Self.build(Self.makePackage(), seed: seed)
        let kept = try FileManager.default.contentsOfDirectory(atPath: seed.path)

        #expect(kept.contains { $0.hasSuffix(".sdkstatcache") }, "the seed holds \(kept)")
        #expect(!kept.contains { $0.hasSuffix(".partial") }, "the seed holds \(kept)")
    }

    @Test("Both spellings of the native build system are recognised")
    func nativeSpellings() {
        #expect(TestSources.selectsNativeBuildSystem(["--build-system", "native"]))
        #expect(TestSources.selectsNativeBuildSystem(["-c", "release", "--build-system=native"]))
        #expect(!TestSources.selectsNativeBuildSystem(["--build-system", "swiftbuild"]))
        #expect(!TestSources.selectsNativeBuildSystem(["-c", "release"]))
    }
}
