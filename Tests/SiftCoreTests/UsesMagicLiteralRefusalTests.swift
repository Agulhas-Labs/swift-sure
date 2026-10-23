//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers `uses:` refusing a `#` token it can never match, rather than answering an empty list that reads as "unused".
@Suite(.temporaryDirectories)
struct UsesMagicLiteralRefusalTests {
    private static func refusal(_ query: String) -> String {
        do {
            _ = try StructuralQuery(query)
            return ""
        } catch {
            return String(describing: error)
        }
    }

    @Test(arguments: ["#filePath", "#file", "#line", "#function", "#Preview", "#expect"])
    func aMagicLiteralOrMacroIsRefusedInOneLineNamingTheRoute(token: String) {
        let message = Self.refusal("uses:\(token)")

        #expect(message == "uses:\(token) — uses: matches names a body references; \(token) is a magic literal or macro, which it cannot match; to find where it is written, git grep '\(token)'")
    }

    @Test
    func theRefusalReachesAnAlternativeAndANegatedTerm() {
        #expect(Self.refusal("kind:func uses:Foo|#filePath").contains("git grep '#filePath'"))
        #expect(Self.refusal("!uses:#line").contains("git grep '#line'"))
    }

    @Test
    func aNameUseAndACallStayAnswerable() throws {
        _ = try StructuralQuery("uses:filePath")
        _ = try StructuralQuery("calls:Preview")
    }

    /// The scan is never asked: a file that writes the literal is not answered "removed all N declaration(s)".
    @Test
    func aSearchForAWrittenLiteralThrowsInsteadOfAnsweringNoMatch() async throws {
        let root = try TestSources.makeTempRepo()
        try TestSources.write("struct Loader {\n    func here() -> String { #filePath }\n}\n", to: "Sources/App/Loader.swift", in: root)
        try TestSources.commitAll(in: root, message: "fixture")

        await #expect(throws: EngineError.self) {
            _ = try await SiftEngine(directory: root).search(query: "uses:#filePath")
        }
    }
}
