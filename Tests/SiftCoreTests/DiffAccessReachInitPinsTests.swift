//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with uses name-matched counts an implicit-member `init(` call in a file of another module as a use of every initializer of each module the build files let that module reach, imported or not.
@Suite(.temporaryDirectories)
struct DiffAccessReachInitPinsTests {
    /// Narrowing the initializer of `Crate4` to `internal` fails: `GizmoTools` imports only `GizmoCore`, which re-exports `GizmoKit`.
    @Test func anImplicitInitializerReachingTheTypeThroughAReExportAllowsPackage() async throws {
        let answer = try await Self.diff(caller: "import GizmoCore\n\nfunc refill(_ holder: inout Holder4) {\n    holder.crate = \(Self.implicitInit)\n}\n")

        #expect(answer.contains("  + GizmoKit.Crate4\(Self.implicitInit)  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }

    /// Narrowing the initializer of `Crate4` to `internal` fails: `GizmoTools` imports `GizmoExtras`, which returns a `Holder4`, and sets its crate without importing `GizmoKit`.
    @Test func anImplicitInitializerOnAValueAnotherModuleReturnsAllowsPackage() async throws {
        let answer = try await Self.diff(caller: "import GizmoExtras\n\nfunc refill() {\n    var held = relayHolder()\n    held.crate = \(Self.implicitInit)\n}\n")

        #expect(answer.contains("  + GizmoKit.Crate4\(Self.implicitInit)  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }

    /// A module whose manifest dependencies do not lead to `GizmoKit` cannot build its types, so its implicit-member calls count for nothing.
    @Test func anImplicitInitializerInAModuleThatCannotReachItLeavesInternal() async throws {
        let answer = try await Self.diff(caller: "func stamp() -> Int {\n    let value: Int = \(Self.implicitInit)\n    return value\n}\n", at: "Sources/GizmoApart/Later.swift")

        #expect(answer.contains("  + GizmoKit.Crate4\(Self.implicitInit)  Sources/GizmoKit/Added.swift:2  public → internal: no use by that name outside module GizmoKit"), "\(answer)")
    }

    /// A module that cannot reach `GizmoKit` through the manifest still counts when its file imports it: importing the module is always a use.
    @Test func anImplicitInitializerInAModuleImportingItDirectlyAllowsPackage() async throws {
        let answer = try await Self.diff(caller: "import GizmoKit\n\nfunc stamp(_ holder: inout Holder4) {\n    holder.crate = \(Self.implicitInit)\n}\n", at: "Sources/GizmoApart/Later.swift")

        #expect(answer.contains("  + GizmoKit.Crate4\(Self.implicitInit)  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoApart, in this package"), "\(answer)")
    }

    /// A module reached through a dependency of its dependencies counts.
    @Test func anImplicitInitializerInAModuleReachingItTransitivelyAllowsPackage() async throws {
        let answer = try await Self.diff(caller: "func stamp(_ holder: inout Holder4) {\n    holder.crate = \(Self.implicitInit)\n}\n", at: "Sources/GizmoOuter/Later.swift")

        #expect(answer.contains("  + GizmoKit.Crate4\(Self.implicitInit)  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoOuter, in this package"), "\(answer)")
    }

    /// A module of an XcodeGen project is in no manifest, so what it can reach is unknown and its implicit-member call counts: the initializer keeps its level, as an Xcode project gets no `package` suggestion.
    @Test func anImplicitInitializerInAnXcodeGenModuleCounts() async throws {
        let root = try Self.depotRoot()
        try TestSources.write("name: GizmoApp\ntargets:\n  GizmoApp:\n    type: application\n    sources:\n      - path: App\n", to: "project.yml", in: root)
        try TestSources.write("func launch() {}\n", to: "App/Launch.swift", in: root)
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write(Self.crate, to: "Sources/GizmoKit/Added.swift", in: root)
        try TestSources.write("func launch(_ holder: inout Holder4) {\n    holder.crate = \(Self.implicitInit)\n}\n", to: "App/Launch.swift", in: root)

        let answer = try await DiffEngineTests.diff(root)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate4\(Self.implicitInit)"), "\(answer)")
    }
}

extension DiffAccessReachInitPinsTests {
    static let implicitInit = DiffAccessInitializerExposurePinsTests.implicitInit

    /// `Crate4`, with a holder whose property a client sets, added to `GizmoKit`.
    static var crate: String {
        """
        public struct Crate4 {
            public init() {}
        }

        public struct Holder4 {
            public var crate: Crate4

            public init() {
                crate = Crate4()
            }

            public init(crate: Crate4) {
                self.crate = crate
            }
        }
        """
    }

    /// A repository whose manifest has `GizmoCore` re-exporting `GizmoKit`, `GizmoExtras` returning its values, `GizmoTools` depending on both, `GizmoOuter` depending on `GizmoTools`, and `GizmoApart` depending on nothing.
    static func depotRoot() throws -> URL {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("""
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Depot",
            targets: [
                .target(name: "GizmoKit"),
                .target(name: "GizmoCore", dependencies: ["GizmoKit"]),
                .target(name: "GizmoExtras", dependencies: [.target(name: "GizmoKit")]),
                .target(name: "GizmoTools", dependencies: ["GizmoCore", .byName(name: "GizmoExtras")]),
                .target(name: "GizmoOuter", dependencies: ["GizmoTools"]),
                .target(name: "GizmoApart"),
            ]
        )
        """, to: "Package.swift", in: root)
        try TestSources.write("@_exported import GizmoKit\n", to: "Sources/GizmoCore/Facade.swift", in: root)
        try TestSources.write("import GizmoKit\n\npublic func relayHolder() -> Holder4 {\n    Holder4()\n}\n", to: "Sources/GizmoExtras/Relay.swift", in: root)
        for target in ["GizmoTools", "GizmoOuter", "GizmoApart"] {
            try TestSources.write("func run() {}\n", to: "Sources/\(target)/Tool.swift", in: root)
        }
        return root
    }

    /// The diff of a working tree that adds `crate` to `GizmoKit` and `caller` at `path`.
    static func diff(caller: String, at path: String = "Sources/GizmoTools/Later.swift") async throws -> String {
        let root = try Self.depotRoot()
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write(Self.crate, to: "Sources/GizmoKit/Added.swift", in: root)
        try TestSources.write(caller, to: path, in: root)
        return try await DiffEngineTests.diff(root)
    }
}
