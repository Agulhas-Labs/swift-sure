//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SiftCore
import Testing

/// A package scheme's `-showBuildSettings` list is empty, so the products directory is found from the DerivedData folder made for the package directory.
@Suite(.temporaryDirectories)
struct PackageProductsDirectoryTests {
    @Test
    func theFolderMadeForThisCheckoutIsChosenAmongFoldersOfTheSameName() throws {
        let fixture = try Fixture.make()

        let path = try PackageProductsDirectory.resolve(workingDirectory: fixture.mine, passThrough: [], derivedDataRoot: fixture.derived)

        #expect(path == fixture.derived.appendingPathComponent("Kit-aaa/Build/Products").path)
    }

    @Test
    func aDerivedDataPathInThePassThroughWinsWithoutSearching() throws {
        let fixture = try Fixture.make()

        let absolute = try PackageProductsDirectory.resolve(
            workingDirectory: fixture.mine,
            passThrough: ["-derivedDataPath", "/elsewhere/derived"],
            derivedDataRoot: fixture.derived.appendingPathComponent("missing")
        )
        let relative = try PackageProductsDirectory.resolve(
            workingDirectory: fixture.mine,
            passThrough: ["-quiet", "-derivedDataPath", ".build/derived"],
            derivedDataRoot: fixture.derived.appendingPathComponent("missing")
        )

        #expect(absolute == "/elsewhere/derived/Build/Products")
        #expect(relative == fixture.mine.appendingPathComponent(".build/derived/Build/Products").path)
    }

    @Test
    func noFolderForThePackageIsRefusedNamingWhereItLooked() throws {
        let fixture = try Fixture.make()
        let stranger = fixture.derived.deletingLastPathComponent().appendingPathComponent("Gizmo-checkout")

        let error = try #require(throws: TestInvocationError.self) {
            try PackageProductsDirectory.resolve(workingDirectory: stranger, passThrough: [], derivedDataRoot: fixture.derived)
        }

        #expect(error.description.contains("settings list was empty"))
        #expect(error.description.contains(fixture.derived.path))
        #expect(error.description.contains("found 0"))
    }

    @Test
    func twoFoldersForThePackageAreRefusedNamingBoth() throws {
        let fixture = try Fixture.make()
        try Fixture.write(workspace: fixture.mine, into: fixture.derived.appendingPathComponent("Kit-ddd"))

        let error = try #require(throws: TestInvocationError.self) {
            try PackageProductsDirectory.resolve(workingDirectory: fixture.mine, passThrough: [], derivedDataRoot: fixture.derived)
        }

        #expect(error.description.contains("found 2"))
        #expect(error.description.contains("Kit-aaa"))
        #expect(error.description.contains("Kit-ddd"))
    }

    @Test
    func onlyAnEmptyListIsTakenForAPackageScheme() {
        #expect(PackageProductsDirectory.isEmptySettings(Data("[]".utf8)))
        #expect(PackageProductsDirectory.isEmptySettings(Data(" [ ] \n".utf8)))
        #expect(!PackageProductsDirectory.isEmptySettings(Data(#"[{"buildSettings":{"BUILD_DIR":"/x"}}]"#.utf8)))
        #expect(!PackageProductsDirectory.isEmptySettings(Data("** BUILD FAILED **".utf8)))
    }

    /// The whole run, with a package scheme's empty settings list: the `.xctestrun` the enumeration is handed sits under the folder made for this checkout.
    @Test
    func aRunWithEmptySettingsEnumeratesFromTheMatchingFolder() throws {
        let fixture = try Fixture.make()
        let events = TestRunTests.Recorder()
        var fake = TestRunTests.Fake(root: fixture.mine)
        fake.settingsJSON = "[]"
        fake.derivedDataRoot = fixture.derived

        let result = TestRun(request: TestRunTests.request(in: fixture.mine), environment: fake.environment(events)).run()

        let expected = fixture.derived.appendingPathComponent("Kit-aaa/Build/Products/\(TestRunTests.Fake.xctestrunName)").path
        let handed = events.launches().compactMap { argv in argv.firstIndex(of: "-xctestrun").map { argv[$0 + 1] } }

        #expect(result.exitCode != 64)
        #expect(handed.contains(expected))
    }

    @Test
    func aRunWithEmptySettingsAndNoFolderIsRefusedBeforeAnythingIsEnumerated() throws {
        let fixture = try Fixture.make()
        let events = TestRunTests.Recorder()
        var fake = TestRunTests.Fake(root: fixture.mine)
        fake.settingsJSON = "[]"
        fake.derivedDataRoot = fixture.derived.appendingPathComponent("missing")

        let result = TestRun(request: TestRunTests.request(in: fixture.mine), environment: fake.environment(events)).run()

        #expect(result.exitCode == 64)
        #expect(result.answer.contains("settings list was empty"))
        #expect(!events.taken().contains("enumerate"))
    }

    @Test
    func aRunNamingAProjectKeepsTheNoBuildDirectoryRefusalForEmptySettings() throws {
        let fixture = try Fixture.make()
        let events = TestRunTests.Recorder()
        var fake = TestRunTests.Fake(root: fixture.mine)
        fake.settingsJSON = "[]"
        fake.derivedDataRoot = fixture.derived
        let request = TestRunRequest(
            scheme: "Kit",
            deviceTypeName: "iPhone 17",
            container: .project("Kit.xcodeproj"),
            workingDirectory: fixture.mine,
            repositoryRoot: fixture.mine,
            executable: fixture.mine.appendingPathComponent("swift-sure")
        )

        let result = TestRun(request: request, environment: fake.environment(events)).run()

        #expect(result.exitCode == 64)
        #expect(result.answer.contains("named no BUILD_DIR"))
    }

    /// A folder is found whichever spelling of the package directory each side holds: the working directory reached through a symlink finds a folder that recorded the real path, and a folder that recorded the symlink is found from the real path.
    @Test
    func aSymlinkedSpellingOfThePackageDirectoryFindsTheSameFolder() throws {
        let fixture = try Fixture.make()
        let link = fixture.root.appendingPathComponent("link-to-kit")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.mine)
        let expected = fixture.derived.appendingPathComponent("Kit-aaa/Build/Products").path

        let throughTheLink = try PackageProductsDirectory.resolve(workingDirectory: link, passThrough: [], derivedDataRoot: fixture.derived)

        let recordedLink = fixture.root.appendingPathComponent("derived-linked")
        try Fixture.write(workspace: link, into: recordedLink.appendingPathComponent("Kit-ddd"))
        let fromTheRealPath = try PackageProductsDirectory.resolve(workingDirectory: fixture.mine, passThrough: [], derivedDataRoot: recordedLink)

        #expect(throughTheLink == expected)
        #expect(fromTheRealPath == recordedLink.appendingPathComponent("Kit-ddd/Build/Products").path)
    }
}

extension PackageProductsDirectoryTests {
    /// A DerivedData root with two folders named `Kit-…` for two checkouts, and an unrelated one.
    struct Fixture {
        let root: URL
        let derived: URL
        let mine: URL

        static func make() throws -> Fixture {
            let root = try TemporaryDirectory.make("package-products")
            let derived = root.appendingPathComponent("DerivedData")
            let mine = root.appendingPathComponent("checkout-one/Kit")
            let theirs = root.appendingPathComponent("checkout-two/Kit")
            let manager = FileManager.default
            for directory in [mine, theirs, root.appendingPathComponent("Gizmo")] {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try write(workspace: mine, into: derived.appendingPathComponent("Kit-aaa"))
            try write(workspace: theirs, into: derived.appendingPathComponent("Kit-bbb"))
            try write(workspace: root.appendingPathComponent("Gizmo"), into: derived.appendingPathComponent("Gizmo-ccc"))
            return Fixture(root: root, derived: derived, mine: mine)
        }

        /// A DerivedData folder for `workspace`, with its `Build/Products` directory.
        static func write(workspace: URL, into folder: URL) throws {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("Build/Products"), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspace.path], format: .xml, options: 0)
            try plist.write(to: folder.appendingPathComponent("info.plist"))
        }
    }
}
