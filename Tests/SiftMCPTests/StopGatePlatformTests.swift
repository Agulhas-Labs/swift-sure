//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftMCP
import Testing

/// The Stop block names the xcodebuild the session ran first, and `swift build` only for a package that does not leave macOS out.
@Suite(.temporaryDirectories)
struct StopGatePlatformTests {
    private static var build: String {
        "swift-sure run -- xcodebuild -scheme Gizmo -destination 'generic/platform=iOS Simulator' build"
    }

    private func manifest(_ platforms: String?) -> String {
        let line = platforms.map { "    platforms: \($0),\n" } ?? ""
        return "// swift-tools-version:6.0\nimport PackageDescription\nlet package = Package(\n    name: \"Depot\",\n\(line)    targets: [.target(name: \"Depot\", swiftSettings: [.define(\"X\", .when(platforms: [.macOS]))])]\n)\n"
    }

    /// The reason the Stop hook blocks with in a package declaring `platforms`, after an edit and, where `session`, a failed xcodebuild of the session.
    private func block(platforms: String?, session: Bool) async throws -> String? {
        let fixture = try StopGateFixture()
        try manifest(platforms).write(to: fixture.repo.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let edited = try fixture.file("Sources/App/Probe.swift")
        var lines: [[String: Any]] = []
        if session {
            lines += [StopGateFixture.bash("t1", command: Self.build, cwd: fixture.repo.path), StopGateFixture.result("t1", failed: true)]
        }
        lines += [StopGateFixture.edit("t2", path: edited), StopGateFixture.result("t2")]
        let transcript = try fixture.transcript(lines)
        return try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript]))
    }

    @Test
    func anIOSPackageWithASessionXcodebuildNamesTheXcodebuild() async throws {
        let reason = try #require(try await block(platforms: "[.iOS(.v17)]", session: true))

        #expect(reason.contains("`\(Self.build)` and"))
        #expect(!reason.contains("swift build"))
    }

    @Test
    func anIOSPackageWithoutAnXcodebuildIsBlockedWithNoCommand() async throws {
        let reason = try #require(try await block(platforms: "[.iOS(.v17)]", session: false))

        #expect(!reason.contains("swift-sure run -- swift build"))
        #expect(reason.contains("declares iOS and not macOS"))
        #expect(reason.contains("may not build it"))
        #expect(!reason.contains("would not build"))
        #expect(reason.contains("xcodebuild"))
    }

    @Test
    func aPackageWithMacOSNamesSwiftBuild() async throws {
        let reason = try #require(try await block(platforms: "[.iOS(.v17), .macOS(.v14)]", session: false))

        #expect(reason.contains("swift-sure run -- swift build"))
    }

    @Test
    func aPackageWithNoPlatformsNamesSwiftBuild() async throws {
        let reason = try #require(try await block(platforms: nil, session: false))

        #expect(reason.contains("swift-sure run -- swift build"))
    }

    @Test
    func macCatalystIsNotMacOS() async throws {
        let reason = try #require(try await block(platforms: "[.macCatalyst(.v17), .iOS(.v17)]", session: false))

        #expect(!reason.contains("swift-sure run -- swift build"))
        #expect(reason.contains("and not macOS, so"))
    }

    @Test
    func aMacOSPackageWithASessionXcodebuildNamesTheXcodebuild() async throws {
        let reason = try #require(try await block(platforms: "[.macOS(.v14)]", session: true))

        #expect(reason.contains("`\(Self.build)` and"))
        #expect(!reason.contains("swift build"))
    }

    @Test
    func theBlockIsAskedOnlyOncePerTree() async throws {
        let fixture = try StopGateFixture()
        try manifest("[.iOS(.v17)]").write(to: fixture.repo.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let transcript = try fixture.transcript([StopGateFixture.edit("t2", path: fixture.file("Sources/App/Probe.swift")), StopGateFixture.result("t2")])

        #expect(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])) != nil)
        #expect(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])) == nil)
    }

    @Test(arguments: [
        ("platforms: [.iOS(.v17)]", ["iOS"]),
        ("platforms: [.macOS(.v14), .iOS(.v17), .tvOS(\"17.0\")]", ["macOS", "iOS", "tvOS"]),
        ("platforms: [.macCatalyst(.v17), .iOS(.v17)]", ["macCatalyst", "iOS"]),
        ("platforms: [\n  // .macOS(.v14),\n  .iOS(.v17),\n]", ["iOS"]),
        ("platforms: [.iOS(.v17)], dependencies: [.package(url: \"https://example.com/platforms: [.macOS]\", from: \"1.0.0\")]", ["iOS"]),
    ])
    func theHelperListsDeclaredPlatformsInOrder(arguments: String, expected: [String]) {
        #expect(ManifestPlatforms.declared(in: "let package = Package(name: \"Gizmo\", \(arguments))") == expected)
    }

    @Test
    func theHelperIgnoresAWhenAndAManifestWithNoPlatforms() {
        #expect(ManifestPlatforms.declared(in: "let package = Package(name: \"Gizmo\", targets: [.target(name: \"G\", swiftSettings: [.define(\"X\", .when(platforms: [.iOS]))])])") == nil)
        #expect(ManifestPlatforms.declared(in: "let package = Package(name: \"Gizmo\")") == nil)
        #expect(ManifestPlatforms.declared(in: "let package = Package(name: \"Gizmo\", platforms: Depot.all)") == nil)
    }

    @Test
    func aPlatformsListJoinedByPlusIsNotReadAndNamesSwiftBuild() async throws {
        let joined = "[.iOS(.v17)] + [.macOS(.v14)]"
        #expect(ManifestPlatforms.declared(in: "let package = Package(name: \"Gizmo\", platforms: \(joined))") == nil)
        let reason = try #require(try await block(platforms: joined, session: false))

        #expect(reason.contains("swift-sure run -- swift build"))
    }

    @Test
    func aManifestWithTwoPackageCallsIsNotReadAndNamesSwiftBuild() async throws {
        let text = "#if os(iOS)\nlet package = Package(name: \"G\", platforms: [.iOS(.v17)])\n#else\nlet package = Package(name: \"G\", platforms: [.macOS(.v14)])\n#endif\n"
        #expect(ManifestPlatforms.declared(in: text) == nil)

        let fixture = try StopGateFixture()
        try text.write(to: fixture.repo.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let edited = try fixture.file("Sources/App/Probe.swift")
        let transcript = try fixture.transcript([StopGateFixture.edit("t2", path: edited), StopGateFixture.result("t2")])
        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("swift-sure run -- swift build"))
    }
}
