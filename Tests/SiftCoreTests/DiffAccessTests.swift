//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section: what the build reads for it, and the section as a range renders it.
@Suite(.temporaryDirectories)
struct DiffAccessTests {
    @Test func theManifestReaderReadsLibraryProductsAndTheToolsVersion() {
        let manifest = SwiftPMManifest.parse(source: """
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "Depot",
            products: [.library(name: "GizmoKit", targets: ["GizmoKit"]), .executable(name: "depot", targets: ["GizmoTools"])],
            targets: [.target(name: "GizmoKit"), .executableTarget(name: "GizmoTools")]
        )
        """)

        #expect(manifest.libraryTargets == ["GizmoKit"])
        #expect(manifest.toolsVersion == [5, 10])
        #expect(SwiftPMManifest.parse(source: "import PackageDescription\n").toolsVersion == nil)
    }

    @Test func theImportReaderTellsTestableImportsApart() {
        let source = "import Testing\n@testable import GizmoKit\nimport WidgetKit\n"

        #expect(ImportLineReader.testableModules(inSource: source) == ["GizmoKit"])
    }

    @Test func aPublicDeclarationWithNoOutsideUseIsNamedByThatNameNeverUnused() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("""
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [.target(name: "GizmoKit"), .target(name: "GizmoTools", dependencies: ["GizmoKit"])]
        )
        """, to: "Package.swift", in: root)
        try TestSources.write("struct Gizmo {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("enum Tool {}\n", to: "Sources/GizmoTools/Tool.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")
        try TestSources.write("struct Gizmo {}\npublic func restock() {}\npackage func shelve() {}\n", to: "Sources/GizmoKit/Gizmo.swift", in: root)
        try TestSources.write("import GizmoKit\nenum Tool {\n    static func run() { restock() }\n}\n", to: "Sources/GizmoTools/Tool.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("access: this range put 1 declaration at public, 1 used only inside its package; 1 at package, 1 with no use outside module GizmoKit"))
        #expect(answer.contains("  + GizmoKit.restock()  Sources/GizmoKit/Gizmo.swift:2  public → package: used only from GizmoTools, in this package"))
        #expect(answer.contains("  + GizmoKit.shelve()  Sources/GizmoKit/Gizmo.swift:3  package → internal: no use by that name outside module GizmoKit"))
        #expect(!answer.contains("unused"))
    }
}
