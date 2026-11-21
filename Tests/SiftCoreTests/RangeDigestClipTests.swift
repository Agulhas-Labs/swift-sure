//
// Copyright © Agulhas Labs
//

@testable import SiftCore
import Testing

/// Covers a cited line range that cuts into a long function: the lines inside the range are served under a header naming the function, where the whole function would be many times the window.
@Suite(.temporaryDirectories)
struct RangeDigestClipTests {
    private static var path: String {
        "Sources/Gizmo/Ledger.swift"
    }

    private static func function(_ name: String, lines: Int) -> [String] {
        ["func \(name)() {"] + (1 ... lines - 2).map { "    _ = \"\(name)-\($0)\"" } + ["}"]
    }

    private static func render(_ functions: [(String, Int)], _ range: String, offset: Int = 0) throws -> String {
        let source = functions.flatMap { function($0.0, lines: $0.1) }.joined(separator: "\n") + "\n"
        let store = try TestSources.makeStore()
        let root = try TestSources.makeTempDirectory()
        let parsed = try TestSources.parsed(source, path: path, in: root)
        try store.replaceFiles([parsed]) { _ in ("Gizmo", false) }
        let renderer = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: root)
        return try renderer.render(target: "\(path):\(range)", options: DigestOptions(offset: offset))
    }

    @Test
    func aRangeStartingInsideALongFunctionAndRunningIntoTheNextClipsTheLongOneAndServesTheShortOneWhole() throws {
        // `tall()` is `:1-100`, `flat()` is `:101-103`.
        let output = try Self.render([("tall", 100), ("flat", 3)], "80-102")

        #expect(output.contains("\(Self.path) lines 80-100, in Gizmo.tall() — func — :1-100 (100 lines; digest Gizmo.tall() for all of it)"))
        #expect(output.contains("Gizmo.flat() — func — \(Self.path):101-103"))
        #expect(!output.contains("tall-78"))
        #expect(output.contains("tall-79"))
        #expect(output.components(separatedBy: "\n").count <= (102 - 80 + 1) + 2 * 2 + 2)
    }

    @Test
    func aRangeStartingBeforeALongFunctionAndEndingInsideItClipsTheFunction() throws {
        // `flat()` is `:1-3`, `tall()` is `:4-103`.
        let output = try Self.render([("flat", 3), ("tall", 100)], "2-40")

        #expect(output.contains("\(Self.path) lines 4-40, in Gizmo.tall() — func — :4-103 (100 lines; digest Gizmo.tall() for all of it)"))
        #expect(!output.contains("tall-37"))
        #expect(output.contains("tall-36"))
        #expect(output.components(separatedBy: "\n").count <= (40 - 2 + 1) + 2 * 2 + 2)
    }

    @Test
    func aFunctionOverhangingTheRangeByThreeLinesOrFewerIsServedWhole() throws {
        // `flat()` is `:1-3`, `tall()` is `:4-103`; the range ends 2 lines short of it.
        let output = try Self.render([("flat", 3), ("tall", 100)], "2-101")

        #expect(!output.contains("for all of it"))
        #expect(output.contains("tall-98"))
    }

    @Test
    func aClippedBlockPastTheBodyCapPagesAndTheResumeServesTheRest() throws {
        // `tall()` is `:1-400`, `flat()` is `:401-403`; the range holds 251 lines of `tall()`.
        let first = try Self.render([("tall", 400), ("flat", 3)], "150-402")

        #expect(first.contains("\(Self.path) lines 150-400, in Gizmo.tall()"))
        #expect(first.contains("… truncated: 51 more lines — "))
        #expect(first.contains("\(Self.path):150-400"))
        #expect(!first.contains("tall-349"))

        let rest = try Self.render([("tall", 400), ("flat", 3)], "150-400", offset: 200)

        #expect(rest.contains("(…200 lines skipped)"))
        #expect(rest.contains("tall-398"))
    }

    @Test(arguments: [(30, 31), (25, 34)])
    func aRangeAcrossTwoLeavesThatFitTheStretchFloorStillClipsEachToItsOwnLines(first: Int, last: Int) throws {
        // `a()` is `:1-30`, `b()` is `:31-60`: together within the whole-leaf stretch floor.
        let output = try Self.render([("a", 30), ("b", 30)], "\(first)-\(last)")

        #expect(output.components(separatedBy: "\n").count <= (last - first + 1) + 2 * 2 + 2)
        #expect(output.contains("lines \(first)-30, in Gizmo.a()"))
        #expect(output.contains("lines 31-\(last), in Gizmo.b()"))
        #expect(!output.contains("a-1\""))
        #expect(!output.contains("b-28\""))
    }
}
