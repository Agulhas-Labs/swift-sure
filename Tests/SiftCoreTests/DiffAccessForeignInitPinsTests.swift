//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// `swift-sure diff`'s access section with uses name-matched counts an implicit-member `init(` call in a file of another module as a use of every initializer of each module that file imports.
@Suite(.temporaryDirectories)
struct DiffAccessForeignInitPinsTests {
    /// Narrowing `Crate.init()` to `internal` fails with "'Crate' initializer is inaccessible due to 'internal' protection level": `GizmoTools` builds it by implicit member without spelling it.
    @Test func anImplicitInitializerInAnotherModuleImportingItAllowsPackage() async throws {
        let answer = try await Self.diff(caller: Self.refill, at: "Sources/GizmoTools/Later.swift")

        #expect(answer.contains("  + GizmoKit.Crate.init()  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }

    /// A file of another module that depends on this module calls an initializer by implicit member without importing it: the type may reach it through a value, so `package` is the floor.
    @Test func anImplicitInitializerInAModuleReachingItWithoutImportingItAllowsPackage() async throws {
        let answer = try await Self.diff(caller: "import Foundation\n\nfunc stamp() -> Date {\n    \(DiffAccessInitializerExposurePinsTests.implicitInit)\n}\n", at: "Sources/GizmoTools/Later.swift")

        #expect(answer.contains("  + GizmoKit.Crate.init()  Sources/GizmoKit/Added.swift:2  public → package: used only from GizmoTools, in this package"), "\(answer)")
    }

    /// Narrowing `Crate.init()` to `package` fails where the implicit-member call sits in a module of another `Package.swift`: it keeps its level, with no line.
    @Test func anImplicitInitializerInAnotherPackageKeepsTheLevel() async throws {
        let answer = try await Self.diff(caller: Self.refill, at: "Tools/Sources/WidgetKit/Later.swift", otherPackage: true)

        #expect(answer.contains("uses name-matched over the working tree"), "\(answer)")
        #expect(!answer.contains("GizmoKit.Crate.init()"), "\(answer)")
    }
}

extension DiffAccessForeignInitPinsTests {
    /// A function of another module that sets a `Holder`'s crate by implicit member, never spelling `Crate`.
    static let refill = "import GizmoKit\n\nfunc refill(_ holder: inout Holder) {\n    holder.crate = \(DiffAccessInitializerExposurePinsTests.implicitInit)\n}\n"

    /// `Crate`, with a holder whose property a client sets, added to `GizmoKit`.
    static var crate: String {
        """
        public struct Crate {
            public init() {}
        }

        public struct Holder {
            public var crate: Crate

            init(crate: Crate) {
                self.crate = crate
            }
        }
        """
    }

    /// The diff of a working tree that adds `crate` to `GizmoKit` and `caller` at `path`, with a second package under `Tools/` where asked.
    static func diff(caller: String, at path: String, otherPackage: Bool = false) async throws -> String {
        let root = try DiffAccessRepoPinsTests.depot()
        if otherPackage {
            try DiffAccessRepoPinsTests.writeOtherPackage(in: root, target: ".target(name: \"WidgetKit\")")
        }
        try DiffAccessRepoPinsTests.commitBase(in: root)
        try TestSources.write(Self.crate, to: "Sources/GizmoKit/Added.swift", in: root)
        try TestSources.write(caller, to: path, in: root)
        return try await DiffEngineTests.diff(root)
    }
}
