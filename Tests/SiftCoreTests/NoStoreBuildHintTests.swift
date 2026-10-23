//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A no-store line names the one build command its root needs: SwiftPM's alone for a package, both forms where an Xcode project sits at the root or there is no package.
@Suite(.temporaryDirectories)
struct NoStoreBuildHintTests {
    private static func root(_ shape: Shape) throws -> URL {
        let root = try TemporaryDirectory.make("no-store-build-hint")
        switch shape {
        case .packageOnly, .packageAndProject:
            try "// swift-tools-version:6.0\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        case .noPackage:
            break
        }
        if case .packageAndProject = shape {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Gizmo.xcodeproj"), withIntermediateDirectories: true)
        }
        return root
    }

    private static func lines(_ shape: Shape) throws -> [String] {
        let root = try root(shape)
        return [
            SiftEngine.storeStatusLine(discovered: nil, rejected: [], root: root, currentDirectory: root.path),
            SiftEngine.noStoreNote(for: WorkingTree(repository: "Depot"), root: root, currentDirectory: root.path),
        ]
    }

    @Test func aPackageAtTheRootIsToldTheSwiftPMCommandAlone() throws {
        for line in try Self.lines(.packageOnly) {
            #expect(line.contains("swift build --build-tests"), "\(line)")
            #expect(!line.contains("xcodebuild"), "\(line)")
            #expect(!line.contains("Discovery searches"), "\(line)")
            #expect(!line.contains("{\"indexStorePath\""), "\(line)")
        }
        let status = try #require(try Self.lines(.packageOnly).first)

        #expect(status.count < 250, "\(status.count): \(status)")
        #expect(status.hasPrefix("index store: none found — build one: \(ProductName.current.binary) run -- swift build --build-tests. "), "\(status)")
    }

    @Test func anXcodeProjectBesideThePackageIsToldBothForms() throws {
        for line in try Self.lines(.packageAndProject) {
            #expect(line.contains("swift build --build-tests"), "\(line)")
            #expect(line.contains("xcodebuild"), "\(line)")
        }
    }

    @Test func noPackageIsToldBothForms() throws {
        for line in try Self.lines(.noPackage) {
            #expect(line.contains("swift build --build-tests"), "\(line)")
            #expect(line.contains("xcodebuild"), "\(line)")
        }
    }

    @Test func theShortPointerNamesTheConfigKeyAndTheGuideSection() throws {
        for line in try Self.lines(.packageOnly) {
            #expect(line.contains("indexStorePath set in \(ProductName.current.configFileName)"), "\(line)")
            #expect(line.contains("§7"), "\(line)")
        }
    }
}

private extension NoStoreBuildHintTests {
    enum Shape {
        case packageOnly, packageAndProject, noPackage
    }
}
