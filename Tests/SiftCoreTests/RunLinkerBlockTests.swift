//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// A link failure's digest keeps the linker's own block — the header, a bounded number of symbols with their first references, and the closing `ld:` line.
struct RunLinkerBlockTests {
    @Test
    func aSwiftBuildLinkFailureAnswersWithTheUndefinedSymbolsBlock() throws {
        let report = try TestSources.runReport("swift-build-linkerror", invokedAs: ["swift", "build"], exitCode: 1)
        let answer = Self.answer(report)

        #expect(answer.contains("Undefined symbols for architecture arm64:"))
        #expect(answer.contains("\"_widget_missing_helper\", referenced from:"))
        #expect(answer.contains("Widget.run() -> () in Widget.o"))
        #expect(answer.contains("ld: symbol(s) not found for architecture arm64"))
    }

    @Test
    func aLongSymbolListKeepsTenSymbolsWithOneReferenceEach() {
        var filter = RunOutputFilter(invokedAs: ["swift", "build"])
        filter.consume(line: "Undefined symbols for architecture arm64:")
        for index in 1 ... 14 {
            filter.consume(line: "  \"_widget_missing_\(index)\", referenced from:")
            filter.consume(line: "      Widget.first\(index)() in Widget.o")
            filter.consume(line: "      Widget.second\(index)() in Widget.o")
        }
        filter.consume(line: "ld: symbol(s) not found for architecture arm64")
        let report = filter.finish(exitCode: 1)

        let block = report.errors.first { $0.message.hasPrefix("Undefined symbols") }

        #expect(block?.detail.filter { $0.contains("referenced from:") }.count == 10)
        #expect(block?.detail.filter { $0.contains("Widget.first") }.count == 10)
        #expect(block?.detail.contains { $0.contains("Widget.second") } == false)
        #expect(block?.detail.contains { $0.contains("_widget_missing_11") } == false)
        #expect(block?.detail.suffix(2) == ["  … and 4 more undefined symbols", "ld: symbol(s) not found for architecture arm64"])
    }

    @Test
    func aPrefixedHeaderOpensTheBlockToo() {
        var filter = RunOutputFilter(invokedAs: ["swift", "build"])
        filter.consume(line: "/Users/dev/Widget/Package.swift: WidgetTests-product: Undefined symbols for architecture arm64:")
        filter.consume(line: "  \"_widget_missing_helper\", referenced from:")
        filter.consume(line: "      Widget.run() -> () in Widget.o")
        filter.consume(line: "ld: symbol(s) not found for architecture arm64")
        let report = filter.finish(exitCode: 1)

        let block = report.errors.first

        #expect(block?.message == "Undefined symbols for architecture arm64:")
        #expect(block?.detail.count == 3)
    }

    @Test
    func aDuplicateSymbolBlockKeepsItsObjectLines() throws {
        let report = try TestSources.runReport("swift-build-duplicate-symbol", invokedAs: ["swift", "build"], exitCode: 1)
        let answer = Self.answer(report)

        #expect(answer.contains("duplicate symbol '_widget_twice' in:"))
        #expect(answer.contains("a.o"))
        #expect(answer.contains("b.o"))
        #expect(answer.contains("ld: 1 duplicate symbols"))
    }

    @Test
    func aDuplicateSymbolBlockIsTheLinkersOwnError() throws {
        let report = try TestSources.runReport("swift-build-duplicate-symbol", invokedAs: ["swift", "build"], exitCode: 1)

        #expect(RunTestSelector.buildFailedFirst(report, exitCode: 1))
    }

    @Test
    func furtherDuplicateHeadersJoinOneBlockAndAreCapped() {
        var filter = RunOutputFilter(invokedAs: ["swift", "build"])
        for index in 1 ... 12 {
            filter.consume(line: "duplicate symbol '_widget_twice_\(index)' in:")
            filter.consume(line: "    /Users/dev/Widget/a.o")
            filter.consume(line: "    /Users/dev/Widget/b.o")
            filter.consume(line: "    /Users/dev/Widget/c.o")
        }
        filter.consume(line: "ld: 12 duplicate symbols")
        let report = filter.finish(exitCode: 1)

        #expect(report.errors.count == 1)
        let block = report.errors.first
        #expect(block?.message == "duplicate symbol '_widget_twice_1' in:")
        #expect(block?.detail.filter { $0.hasPrefix("duplicate symbol ") }.count == 9)
        #expect(block?.detail.filter { $0.hasSuffix("c.o") }.isEmpty == true)
        #expect(block?.detail.suffix(2) == ["  … and 2 more duplicate symbols", "ld: 12 duplicate symbols"])
    }

    @Test
    func aSecondProductsLinkBlockIsKeptAndAnExactRepeatIsNot() {
        var filter = RunOutputFilter(invokedAs: ["swift", "build"])
        for symbol in ["_alpha_missing", "_beta_missing", "_beta_missing"] {
            let product = symbol.hasPrefix("_alpha") ? "AlphaTests-product" : "BetaTests-product"
            filter.consume(line: "/Users/dev/Widget/Package.swift: \(product): Undefined symbols for architecture arm64:")
            filter.consume(line: "  \"\(symbol)\", referenced from:")
            filter.consume(line: "      Widget.run() -> () in Widget.o")
            filter.consume(line: "ld: symbol(s) not found for architecture arm64")
            filter.consume(line: "/Users/dev/Widget/Package.swift: \(product): clang: error: linker command failed with exit code 1")
        }
        let report = filter.finish(exitCode: 1)

        let blocks = report.errors.filter { $0.message.hasPrefix("Undefined symbols") }

        #expect(blocks.count == 2)
        #expect(blocks.first?.detail.contains { $0.contains("_alpha_missing") } == true)
        #expect(blocks.last?.detail.contains { $0.contains("_beta_missing") } == true)
    }

    @Test
    func symbolsAfterAClosingLineOpenTheNextBlockAndAreCountedThere() {
        var filter = RunOutputFilter(invokedAs: ["swift", "build"])
        for index in 1 ... 10 {
            filter.consume(line: "duplicate symbol '_first_\(index)' in:")
            filter.consume(line: "    /Users/dev/Widget/a.o")
        }
        filter.consume(line: "ld: 10 duplicate symbols")
        for index in 1 ... 3 {
            filter.consume(line: "duplicate symbol '_second_\(index)' in:")
            filter.consume(line: "    /Users/dev/Widget/a.o")
        }
        filter.consume(line: "ld: 3 duplicate symbols")
        filter.consume(line: "clang: error: linker command failed with exit code 1 (use -v to see invocation)")
        let report = filter.finish(exitCode: 1)

        #expect(report.errors.count == 2)
        let second = report.errors.last
        #expect(second?.message == "duplicate symbol '_second_1' in:")
        #expect(second?.detail.filter { $0.hasPrefix("duplicate symbol ") }.count == 2)
        #expect(report.errors.first?.detail.contains { $0.contains("_second_") } == false)
    }

    private static func answer(_ report: RunReport) -> String {
        RunReportRenderer(kind: .swiftBuild, workingDirectory: URL(fileURLWithPath: "/Users/dev/Widget")).render(report, exitCode: 1, logURL: nil)
    }
}
