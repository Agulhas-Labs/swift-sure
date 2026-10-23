//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A repository whose packages sit below its root is sent back to build the package that holds the edit.
@Suite(.temporaryDirectories)
struct StopGateNestedPackageTests {
    /// A fixture with no `Package.swift` at the root and a package at each of `packages`, those in `phoneOnly` leaving macOS out, each holding `Sources/<name>/Depot.swift`.
    private func fixture(packages: [String], phoneOnly: Set<String> = []) throws -> StopGateFixture {
        let fixture = try StopGateFixture(package: false)
        for package in packages {
            let directory = fixture.repo.appendingPathComponent(package)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "// swift-tools-version:6.0\nimport PackageDescription\nlet package = Package(name: \"\(package)\"\(phoneOnly.contains(package) ? ", platforms: [.iOS(.v17)]" : ""))\n"
                .write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            _ = try fixture.file("\(package)/Sources/\(package)/Depot.swift")
        }
        _ = try fixture.file("App/Depot.swift")
        return fixture
    }

    private func edit(_ fixture: StopGateFixture, _ paths: [String]) throws -> String {
        var lines: [[String: Any]] = []
        for (index, path) in paths.enumerated() {
            lines.append(StopGateFixture.edit("t\(index)", path: fixture.repo.appendingPathComponent(path).path))
            lines.append(StopGateFixture.result("t\(index)"))
        }
        return try fixture.transcript(lines)
    }

    @Test
    func anEditInANestedPackageNamesItsBuild() async throws {
        let fixture = try fixture(packages: ["Gizmo"])
        let transcript = try edit(fixture, ["Gizmo/Sources/Gizmo/Depot.swift"])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("`(cd \(CanonicalPath.of(fixture.repo.path)) && swift-sure run -- swift build --package-path Gizmo)` and"))
    }

    @Test
    func aGreenWrappedBuildOfThatPackageLetsTheStopThrough() async throws {
        let fixture = try fixture(packages: ["Gizmo"])
        let transcript = try fixture.transcript([
            StopGateFixture.edit("t1", path: fixture.repo.appendingPathComponent("Gizmo/Sources/Gizmo/Depot.swift").path),
            StopGateFixture.result("t1"),
            StopGateFixture.bash("t2", command: "swift-sure run -- swift build --package-path Gizmo", cwd: fixture.repo.path),
            StopGateFixture.result("t2"),
        ])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    @Test
    func editsInTwoPackagesNameBothBuildsInPathOrder() async throws {
        let fixture = try fixture(packages: ["Gizmo", "Depot"])
        let transcript = try edit(fixture, ["Gizmo/Sources/Gizmo/Depot.swift", "Depot/Sources/Depot/Depot.swift"])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        let root = CanonicalPath.of(fixture.repo.path)

        #expect(reason.contains("`(cd \(root) && swift-sure run -- swift build --package-path Depot && swift-sure run -- swift build --package-path Gizmo)` and"))
    }

    @Test
    func anEditOutsideEveryPackageMeansNoBlock() async throws {
        let fixture = try fixture(packages: ["Gizmo"])
        let transcript = try edit(fixture, ["App/Depot.swift"])

        #expect(await fixture.hook(["transcript_path": transcript]).isEmpty)
    }

    @Test
    func anEditInAnIOSOnlyNestedPackageAsksForThePlatformNotABuild() async throws {
        let fixture = try fixture(packages: ["PadKit"], phoneOnly: ["PadKit"])
        let transcript = try edit(fixture, ["PadKit/Sources/PadKit/Depot.swift"])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(!reason.contains("swift-sure run -- swift build"))
        #expect(reason.contains("declares iOS and not macOS"))
        #expect(reason.contains("may not build it"))
    }

    @Test
    func aMacOSPackageBesideAnIOSOnlyOneDoesNotHideTheIOSOnlyEdit() async throws {
        let fixture = try fixture(packages: ["Gizmo", "PadKit"], phoneOnly: ["PadKit"])
        let transcript = try edit(fixture, ["Gizmo/Sources/Gizmo/Depot.swift", "PadKit/Sources/PadKit/Depot.swift"])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(!reason.contains("swift-sure run -- swift build"))
        #expect(reason.contains("declares iOS and not macOS"))
    }
}
