//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
import Testing

/// Covers how a run's answer states a lone failure, which drops the measurement line, and sets apart the blocks of different kinds.
struct RunLoneEntryBlocksTests {
    /// The measurement line is dropped over one entry, so the entry carries its changed-files measurement itself.
    @Test
    func aLoneFailureStatesWhetherItIsInAChangedFile() {
        let changed = Self.answer(Self.loneFailure, changedFiles: .of(["Tests/PalletTests/PalletTests.swift"]))
        let untouched = Self.answer(Self.loneFailure, changedFiles: .of(["Sources/Pallet/Stack.swift"]))

        #expect(changed.contains("  aFailingTest() — PalletTests.swift:11:9 (in a changed file)"))
        #expect(untouched.contains("  aFailingTest() — PalletTests.swift:11:9 (not in a changed file)"))
    }

    /// Where the working tree could not be consulted, the suffix says so rather than reading as zero.
    @Test
    func aLoneFailureSaysWhenChangedFilesAreUnknown() {
        let answer = Self.answer(Self.loneFailure, changedFiles: .unavailable("not a git repository"))

        #expect(answer.contains("  aFailingTest() — PalletTests.swift:11:9 (changed files unknown)"))
    }

    /// Where the working tree was never consulted there is nothing to say, so the failure carries no suffix.
    @Test
    func aLoneFailureCarriesNoSuffixWhereTheTreeWasNotConsulted() {
        let answer = Self.answer(Self.loneFailure, changedFiles: .unavailable(RunChangedFiles.notConsultedReason))

        #expect(answer.contains("  aFailingTest() — PalletTests.swift:11:9"))
        #expect(!answer.contains { $0.contains("changed file") })
    }

    /// A lone compiler error that names a file says so after a dash, set apart from the compiler's own sentence.
    @Test
    func aLoneCompilerErrorStatesItsChangedFileAfterADash() {
        let log = ["/Users/dev/Pallet/Sources/Pallet/Stack.swift:2:15: error: cannot find 'x' in scope"]
        let changed = Self.answer(log, changedFiles: .of(["Sources/Pallet/Stack.swift"]))
        let untouched = Self.answer(log, changedFiles: .of(["Sources/Pallet/Other.swift"]))

        #expect(changed.contains("  Sources/Pallet/Stack.swift:2:15: error: cannot find 'x' in scope — in a changed file"))
        #expect(untouched.contains("  Sources/Pallet/Stack.swift:2:15: error: cannot find 'x' in scope — not in a changed file"))
    }

    /// A lone linker block names no file, so no claim about changed files follows its header, though the tree is known.
    @Test
    func aLoneLinkerBlockCarriesNoSuffix() throws {
        let report = try TestSources.runReport("swift-test-linkerror")
        let answer = RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Widget"), changedFiles: .of(["Sources/Widget/Other.swift"]))
            .render(report, exitCode: 1, logURL: nil)

        #expect(answer.contains("Undefined symbols for architecture arm64:"))
        #expect(!answer.contains("changed file"))
    }

    /// Over several failures the measurement line says it once, so no entry repeats it.
    @Test
    func severalFailuresCarryNoSuffix() {
        let log = [
            "✘ Test aFailingTest() recorded an issue at PalletTests.swift:11:9: Expectation failed: Bool(false)",
            "✘ Test aFailingTest() recorded an issue at PalletTests.swift:21:9: Expectation failed: 1 == 2",
            "✘ Test run with 2 tests in 1 suite failed after 0.010 seconds with 2 issues.",
        ]

        let answer = Self.answer(log, changedFiles: .of([]))

        #expect(answer.contains { $0.contains("2 failures") && $0.contains("0 in changed files") })
        #expect(!answer.contains { $0.contains("(in a changed file)") || $0.contains("(not in a changed file)") })
    }

    /// A lone error, a test failure and a crash each get a block, and a blank line sits between blocks of different kinds.
    @Test
    func anErrorAFailureAndASignalLineAreSetApart() throws {
        let answer = Self.answer(Self.errorFailureCrash, changedFiles: .of([]))

        let error = try #require(answer.firstIndex { $0.contains("error: cannot find") })
        let failure = try #require(answer.firstIndex { $0.hasPrefix("  aFailingTest()") })
        let crash = try #require(answer.firstIndex { $0.contains("exited on signal 11") })

        #expect(answer[crash + 1] == "")
        #expect(answer[error - 1] == "")
        #expect(answer[failure - 1] == "")
    }

    /// A crash line directly above the failures is set apart from them too, with no errors between.
    @Test
    func aSignalLineIsSetApartFromTheFailuresBeneathIt() throws {
        let answer = Self.answer(Array(Self.errorFailureCrash.dropFirst()), changedFiles: .of([]))

        let crash = try #require(answer.firstIndex { $0.contains("exited on signal 11") })
        let failure = try #require(answer.firstIndex { $0.hasPrefix("  aFailingTest()") })

        #expect(answer[crash + 1] == "")
        #expect(failure == crash + 2)
    }
}

private extension RunLoneEntryBlocksTests {
    static let loneFailure = [
        "✘ Test aFailingTest() recorded an issue at PalletTests.swift:11:9: Expectation failed: Bool(false)",
        "✘ Test run with 1 test in 1 suite failed after 0.010 seconds with 1 issue.",
    ]

    static var errorFailureCrash: [String] {
        let helper = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
        return [
            "/Users/dev/Pallet/Sources/Pallet/Stack.swift:2:15: error: cannot find 'x' in scope",
            "◇ Test run started.",
            "◇ Test aFailingTest() started.",
            "✘ Test aFailingTest() recorded an issue at PalletTests.swift:11:9: Expectation failed: Bool(false)",
            "✘ Test aFailingTest() failed after 0.001 seconds with 1 issue.",
            "◇ Test topples() started.",
            "error: Process '\(helper) --test-bundle-path /Users/dev/Pallet/.build/out/Products/Debug/PalletTests.xctest --event-stream-output-path /var/tmp/e.jsonl /Users/dev/Pallet/.build/out/Products/Debug/PalletTests.xctest --testing-library swift-testing' exited with unexpected signal code 11",
        ]
    }

    static func answer(_ log: [String], changedFiles: RunChangedFiles) -> [String] {
        var filter = RunOutputFilter(invokedAs: ["swift", "test"])
        filter.consume(Data((log.joined(separator: "\n") + "\n").utf8))
        let report = filter.finish(exitCode: 1)
        return RunReportRenderer(kind: .swiftTest, workingDirectory: URL(fileURLWithPath: "/Users/dev/Pallet"), changedFiles: changedFiles)
            .render(report, exitCode: 1, logURL: nil)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
