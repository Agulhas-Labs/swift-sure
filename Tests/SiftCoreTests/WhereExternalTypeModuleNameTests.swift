//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `where Dep.member` with no index store, for a `Dep` a file imports as a module of the same name: written bare there it is the type, so the answer says it is declared outside the repository, and written only as a qualifier, `Net.URL`, it is the module, so the wrong-path answer stays.
@Suite(.temporaryDirectories)
struct WhereExternalTypeModuleNameTests {
    /// A dependency module `Tally` whose type `Tally` a file writes bare, a module `Net` a file writes only as the qualifier of its names, and a repository type declaring a `count` and a `host` of its own.
    private static let files = [
        "Sources/GizmoCore/Box.swift": "struct Box {\n    var count: Int { 1 }\n    var host: String { \"\" }\n}\n",
        "Sources/GizmoCore/Use.swift": "import Tally\n\nfunc use() -> Int {\n    let tally: Tally = Tally()\n    return tally.count\n}\n",
        "Sources/GizmoCore/Link.swift": "import Net\n\nfunc link(_ url: Net.URL) -> Net.URL {\n    Net.make(url)\n}\n",
    ]

    /// The answer `where` gives for `symbol` over the fixture, with no index store.
    private static func answer(_ symbol: String) async throws -> String {
        let root = try TestSources.makeTempRepo()
        for (path, source) in files {
            try TestSources.write(source, to: path, in: root)
        }
        try TestSources.commitAll(in: root, message: "a dependency module and its same-named type, unbuilt")
        let engine = try SiftEngine(directory: root)
        return try await engine.lookup(symbol: symbol, freshness: engine.ensureFresh(), options: WhereOptions(includeReferences: true))
    }

    /// A type written bare in a file importing a module of its name is the type, so it is declared outside the repository and the wrong-path wording never appears.
    @Test
    func aBareUseInAFileImportingTheSameNamedModuleIsTheType() async throws {
        let output = try await Self.answer("Tally.count")

        #expect(output.contains("Tally is declared outside this repository"), "\(output)")
        #expect(!output.contains("could not resolve the path"), "\(output)")
    }

    /// A name a file imports as a module and writes only as a qualifier is that module, so a member asked of it keeps the wrong-path answer.
    @Test
    func aQualifierInAFileImportingTheModuleIsTheModule() async throws {
        let output = try await Self.answer("Net.host")

        #expect(!output.contains("declared outside this repository"), "\(output)")
        #expect(output.contains("could not resolve the path Net.host — host is declared, but not under Net:"), "\(output)")
    }
}
