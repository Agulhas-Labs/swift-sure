//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
@testable import SiftMCP
import Testing

/// A `swift-sure run --root` build vouches for the directory it names, and the Stop block names its build as a `--root` run.
@Suite(.temporaryDirectories)
struct StopGateRootRunTests {
    @Test(arguments: [
        ("swift-sure run --root /w/other -- swift build", ["/w/other"]),
        ("swift-sure run --root ../other -- swift test", ["/w/other"]),
        ("cd /w/x && swift-sure run --root sub -- swift build", ["/w/x/sub"]),
        ("swift-sure run --root=/w/other -- swift build", ["/w/other"]),
        ("swift-sure run --root /w/other swift build", ["/w/other"]),
    ])
    func aRunsOwnRootPlacesIt(command: String, directories: [String]) {
        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: command, cwd: "/w/repo") == directories)
    }

    @Test
    func anotherOptionLeavesTheRunWhereItWas() {
        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: "swift-sure run --without Sources -- swift test", cwd: "/w/repo") == ["/w/repo"])
    }

    @Test
    func aRelativeRootWithNoDirectoryPlacesNothing() {
        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: "swift-sure run --root rel -- swift build", cwd: nil).isEmpty)
    }

    @Test
    func aPackageRootIsNamedAsARootRun() throws {
        let root = try TemporaryDirectory.make("stop-root")
        try "// swift-tools-version: 6.0\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let command = StopBuildGate.command(root: root, xcodebuild: nil)

        #expect(command?.command == "swift-sure run --root \(root.path) -- swift build")
        #expect(command?.directory == root.path)
    }

    @Test
    func anXcodebuildRunIsRootedInItsDirectory() throws {
        let root = try TemporaryDirectory.make("stop-root")
        let inside = root.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let written = "swift-sure run -- xcodebuild -scheme Gizmo -destination 'generic/platform=iOS Simulator' build"
        let command = StopBuildGate.command(root: root, xcodebuild: (written, inside.path))
        let canonical = CanonicalPath.of(inside.path)

        #expect(command?.command == "swift-sure run --root \(canonical) -- xcodebuild -scheme Gizmo -destination 'generic/platform=iOS Simulator' build")
    }

    @Test(arguments: [
        ("DEVELOPER_DIR=/X swift-sure run -- xcodebuild -scheme S build", "DEVELOPER_DIR=/X swift-sure run --root %@ -- xcodebuild -scheme S build"),
        ("FOO='a b' swift-sure run -- xcodebuild -scheme S build", "FOO='a b' swift-sure run --root %@ -- xcodebuild -scheme S build"),
    ])
    func leadingAssignmentsStayInFrontOfTheRootedRun(written: String, expected: String) throws {
        let root = try TemporaryDirectory.make("stop-root")
        let canonical = CanonicalPath.of(root.path)
        let command = try #require(StopBuildGate.command(root: root, xcodebuild: (written, root.path)))

        #expect(command.command == expected.replacingOccurrences(of: "%@", with: canonical))
        #expect(BuildInputEditsSinceGreenRun.validatedDirectories(of: command.command, cwd: "/elsewhere").map(CanonicalPath.of) == [canonical])
    }

    @Test
    func anXcodebuildWithItsOwnRootIsWrappedVerbatim() throws {
        let root = try TemporaryDirectory.make("stop-root")
        let written = "swift-sure run --root /x -- xcodebuild -scheme Gizmo build"
        let command = StopBuildGate.command(root: root, xcodebuild: (written, root.path))

        #expect(command?.command == "(cd \(CanonicalPath.of(root.path)) && swift-sure run --root /x -- xcodebuild -scheme Gizmo build)")
    }

    @Test(arguments: [
        ("sift run -- xcodebuild -scheme Gizmo build", "sift run --root %@ -- xcodebuild -scheme Gizmo build"),
        ("~/.local/bin/swift-sure run -- xcodebuild -scheme Gizmo build", "~/.local/bin/swift-sure run --root %@ -- xcodebuild -scheme Gizmo build"),
        ("swift-sure run xcodebuild -scheme Gizmo build", "swift-sure run --root %@ -- xcodebuild -scheme Gizmo build"),
        ("sift run --without Sources -- xcodebuild -scheme Gizmo build", "sift run --root %@ --without Sources -- xcodebuild -scheme Gizmo build"),
    ])
    func anotherSpellingOfTheBinaryIsRootedAsWritten(written: String, expected: String) throws {
        let root = try TemporaryDirectory.make("stop-root")
        let command = StopBuildGate.command(root: root, xcodebuild: (written, root.path))

        #expect(command?.command == expected.replacingOccurrences(of: "%@", with: CanonicalPath.of(root.path)))
    }

    @Test
    func anXcodebuildWithTheRootOfItsDirectoryIsNamedAsWritten() throws {
        let root = try TemporaryDirectory.make("stop-root")
        let canonical = CanonicalPath.of(root.path)
        let written = "sift run --root \(canonical) -- xcodebuild -scheme Gizmo build"
        let command = StopBuildGate.command(root: root, xcodebuild: (written, root.path))

        #expect(command?.command == written)
    }

    @Test
    func anXcodebuildOfUnknownDirectoryNamesNoBuild() throws {
        let root = try TemporaryDirectory.make("stop-root")
        let written = "swift-sure run -- xcodebuild -scheme Gizmo build"
        let command = StopBuildGate.command(root: root, xcodebuild: (written, nil))

        #expect(command == nil)
    }

    @Test
    func aCdOnTheLineIsTheDirectoryTheBuildIsNamedIn() async throws {
        let fixture = try StopGateFixture(package: false, neutralPath: true)
        let edited = try fixture.file("app/A.swift")
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: "cd app && swift-sure run -- xcodebuild -scheme Gizmo build", cwd: fixture.repo.path),
            StopGateFixture.result("t1", failed: true),
            StopGateFixture.edit("t2", path: edited),
            StopGateFixture.result("t2"),
        ])

        let reason = try #require(try await StopGateFixture.blockReason(of: fixture.hook(["transcript_path": transcript])))

        #expect(reason.contains("`swift-sure run --root \(CanonicalPath.of(fixture.repo.path))/app -- xcodebuild -scheme Gizmo build` and"))
    }

    @Test
    func aPushdLeavesNoBuildNamed() async throws {
        let fixture = try StopGateFixture(package: false, neutralPath: true)
        let edited = try fixture.file("app/A.swift")
        let transcript = try fixture.transcript([
            StopGateFixture.bash("t1", command: "pushd app && swift-sure run -- xcodebuild -scheme Gizmo build", cwd: fixture.repo.path),
            StopGateFixture.result("t1", failed: true),
            StopGateFixture.edit("t2", path: edited),
            StopGateFixture.result("t2"),
        ])

        let printed = await fixture.hook(["transcript_path": transcript])

        #expect(try StopGateFixture.blockReason(of: printed) == nil)
    }
}
