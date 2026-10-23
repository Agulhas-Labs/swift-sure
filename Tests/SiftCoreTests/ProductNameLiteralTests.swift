//
// Copyright © Agulhas Labs
//

import Foundation
import SwiftParser
import SwiftSyntax
import Testing

/// Covers that the product's name is spelled in one place: no string or regex literal under `Sources/` outside `ProductName.swift` carries the name's on-disk, environment or tool spellings.
///
/// Every source file is parsed and each text segment of each string literal is checked, so a comment that quotes a name is not held to this and a literal that smuggles one in is found with its file and line.
struct ProductNameLiteralTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent() // SiftCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository root

    /// The one file allowed to spell the name.
    private static var home: String {
        "Sources/SiftCore/ProductName.swift"
    }

    nonisolated(unsafe) private static let hidden = /\.(?:swift-sure|sift)(?![A-Za-z0-9_])/

    /// The name as a word, in the current spelling (binary and display) and the legacy one, so a literal that still spells the previous release's name is found too.
    private static var word: String {
        #"(?i)(?<![A-Za-z0-9_])(?:swift-sure|swiftsure|sift)(?![A-Za-z0-9_])|\\[A-Za-z](?:swift-sure|swiftsure|sift)(?![A-Za-z0-9_])"#
    }

    /// Why a literal segment is a spelling of the name, or `nil` when it is not.
    static func spelling(in text: String) -> String? {
        if text.contains(hidden) {
            return "a hidden state path"
        }
        if text.contains("bak-swift-sure") || text.contains("bak-sift") {
            return "the backup suffix"
        }
        if text.contains("SWIFT_SURE_") || text.contains("SIFT_") {
            return "an environment variable"
        }
        if text.contains("mcp__swift-sure") || text.contains("mcp__sift") {
            return "a tool prefix"
        }
        if text.range(of: word, options: .regularExpression) != nil {
            return "the name as a word"
        }
        return nil
    }

    private static func sourceFiles() -> [URL] {
        let sources = repository.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    }

    @Test
    func noLiteralOutsideTheNameFileSpellsTheName() throws {
        let files = Self.sourceFiles()
        var offences: [String] = []
        for file in files {
            let path = String(file.path.dropFirst(Self.repository.path.count + 1))
            guard path != Self.home else { continue }
            let tree = try Parser.parse(source: String(contentsOf: file, encoding: .utf8))
            let visitor = Segments(tree: tree, path: path)
            visitor.walk(tree)
            for segment in visitor.found {
                if let why = Self.spelling(in: segment.text) {
                    offences.append("\(path):\(segment.line) spells \(why): \(segment.text.prefix(60))")
                }
            }
        }

        #expect(files.count > 300, "only \(files.count) source files were parsed")
        #expect(offences.isEmpty, "route these through ProductName:\n\(offences.joined(separator: "\n"))")
    }

    @Test
    func theCheckRecognisesEachSpelling() {
        #expect(Self.spelling(in: "~/.swift-sure/run.jsonl") != nil)
        #expect(Self.spelling(in: "x.bak-swift-sure") != nil)
        #expect(Self.spelling(in: "SWIFT_SURE_HOME") != nil)
        #expect(Self.spelling(in: "mcp__swift-sure__digest") != nil)
        #expect(Self.spelling(in: "swift-sure") != nil)
        #expect(Self.spelling(in: "swift-sure run") != nil)
        #expect(Self.spelling(in: "run SwiftSure now") != nil)
        #expect(Self.spelling(in: "~/.sift/run.jsonl") != nil)
        #expect(Self.spelling(in: "x.bak-sift") != nil)
        #expect(Self.spelling(in: "SIFT_HOME") != nil)
        #expect(Self.spelling(in: "mcp__sift__digest") != nil)
        #expect(Self.spelling(in: "x-sift-y") != nil)
        #expect(Self.spelling(in: #"/\bsift\b/"#) != nil)
        #expect(Self.spelling(in: #"\tsift"#) != nil)
        #expect(Self.spelling(in: ".siftable") == nil)
        #expect(Self.spelling(in: "SiftCore") == nil)
        #expect(Self.spelling(in: "sift_answer_text") == nil)
    }
}

extension ProductNameLiteralTests {
    /// The text segments of every string literal in one tree, each with its line.
    final class Segments: SyntaxVisitor {
        let converter: SourceLocationConverter
        var found: [(line: Int, text: String)] = []

        init(tree: SourceFileSyntax, path: String) {
            converter = SourceLocationConverter(fileName: path, tree: tree)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind {
            found.append((line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line, text: node.content.text))
            return .skipChildren
        }

        override func visit(_ node: RegexLiteralExprSyntax) -> SyntaxVisitorContinueKind {
            found.append((line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line, text: node.regex.text))
            return .skipChildren
        }
    }
}
