//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

@Suite("The answer a line of shell windows gets")
struct ShellWindowFoldTests {
    /// A temporary directory holding `files`, removed when `body` returns.
    static func inDirectory(_ files: [String: String], _ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShellWindowFoldTests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        for (name, text) in files {
            try text.write(toFile: directory + "/" + name, atomically: true, encoding: .utf8)
        }
        try body(directory)
    }

    /// Eight blocks of six comment lines and a line of code, 56 lines, with the folded text `sed -n 1,56p` prints of them.
    static func commented(_ tag: String = "Widget") -> (file: String, folded: String) {
        var file = ""
        var folded = ""
        for block in 0 ..< 8 {
            let first = block * 7 + 1
            for line in first ... first + 5 {
                file += "// \(tag) note \(line) " + String(repeating: "x", count: 50) + "\n"
            }
            file += "let widget\(block) = \(block)\n"
            folded += "\(first)-\(first + 5): // … 6 comment lines\nlet widget\(block) = \(block)\n"
        }
        return (file, folded)
    }

    static func code(lines: Int) -> String {
        (1 ... lines).map { "let widget\($0) = \(String(repeating: "7", count: 30))" }.joined(separator: "\n") + "\n"
    }

    static func comments(lines: Int) -> String {
        (1 ... lines).map { "// Gizmo note \($0) " + String(repeating: "y", count: 50) }.joined(separator: "\n") + "\n"
    }

    static func answer(_ command: String, in directory: String, parseError: Bool = false) -> ShellWindowFold.Outcome {
        guard let line = ShellWindowLine.reading(command) else { return .letThrough(rule: "unread") }
        return ShellWindowFold.answer(line, in: directory) { _ in parseError }
    }

    @Test("A commented window is answered under its framing line, with the folded text as printed")
    func commentedWindowIsAnswered() throws {
        let sample = Self.commented()
        try Self.inDirectory(["Gizmo.swift": sample.file]) { directory in
            let outcome = Self.answer("sed -n 1,56p Gizmo.swift", in: directory)
            guard case let .answered(text, calls, source, served) = outcome else {
                Issue.record("expected an answer, got \(outcome)")
                return
            }
            #expect(calls == ["window Gizmo.swift:1-56"])
            #expect(source == sample.file.utf8.count)
            #expect(served == text.utf8.count)
            let first = try #require(text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first)
            let head = "\(ProductName.current.binary) answered `window Gizmo.swift:1-56` instead of running it: 48 comment lines in 8 runs folded; the identical command re-run prints them. "
            #expect(first == head + InPlaceAnswer.closingLine(source: source, served: served, standsIn: ""))
            #expect(first.hasSuffix("served (\((source - served) * 100 / source)% smaller)."))
            #expect(text.hasSuffix("\n" + sample.folded))
            #expect(InPlaceAnswer.calls(inOpeningLine: first) == calls)
        }
    }

    @Test("A window of code alone is let through as notSmaller")
    func codeOnlyIsNotSmaller() throws {
        try Self.inDirectory(["Gizmo.swift": Self.code(lines: 60)]) { directory in
            #expect(Self.answer("sed -n 1,50p Gizmo.swift", in: directory) == .letThrough(rule: "notSmaller"))
        }
    }

    @Test("A fold saving a quarter but not the floor is let through as notSmaller")
    func underTheFloor() throws {
        let file = Self.comments(lines: 4) + "let a = 1\n" + Self.comments(lines: 4) + "let b = 2\n"
        try Self.inDirectory(["Gizmo.swift": file]) { directory in
            let outcome = Self.answer("sed -n 1,10p Gizmo.swift", in: directory)
            #expect(outcome == .letThrough(rule: "notSmaller"))
            // The fold itself clears the share: it is the floor that withholds it.
            let line = try #require(ShellWindowLine.reading("sed -n 1,10p Gizmo.swift"))
            let window = try #require(line.windows.first)
            let shown = try #require(window.printed(of: file))
            let fold = try #require(WindowFold.fold(fileText: file, lines: shown.lines, numbering: shown.numbering, commentLines: Set(1 ... 4).union(6 ... 9)))
            #expect(Double(fold.printedBytes - fold.text.utf8.count) / Double(fold.printedBytes) >= ShellWindowFold.foldSavingShare)
            #expect(fold.printedBytes < 1000)
        }
    }

    @Test("A fold saving the floor but not a quarter is let through as notSmaller")
    func underTheShare() throws {
        let file = Self.code(lines: 175) + Self.comments(lines: 20)
        try Self.inDirectory(["Gizmo.swift": file]) { directory in
            #expect(Self.answer("sed -n 1,195p Gizmo.swift", in: directory) == .letThrough(rule: "notSmaller"))
        }
    }

    @Test("A denial past the size budget is let through as overSize")
    func overTheBudget() throws {
        let file = Self.code(lines: 300) + Self.comments(lines: 120)
        try Self.inDirectory(["Gizmo.swift": file]) { directory in
            #expect(Self.answer("sed -n 1,420p Gizmo.swift", in: directory) == .letThrough(rule: "overSize"))
        }
    }

    @Test("A file holding a conflict marker is let through as conflicted")
    func conflictMarker() throws {
        let file = Self.commented().file + "<<<<<<< HEAD\nlet a = 1\n=======\nlet a = 2\n>>>>>>> other\n"
        try Self.inDirectory(["Gizmo.swift": file]) { directory in
            #expect(Self.answer("sed -n 1,56p Gizmo.swift", in: directory) == .letThrough(rule: "conflicted"))
        }
    }

    @Test("A file the index holds with a parse error is let through as parseError")
    func parseError() throws {
        try Self.inDirectory(["Gizmo.swift": Self.commented().file]) { directory in
            #expect(Self.answer("sed -n 1,56p Gizmo.swift", in: directory, parseError: true) == .letThrough(rule: "parseError"))
        }
    }

    @Test("A window whose lines cannot be read off the command is let through as notExact")
    func byteWindowIsNotExact() throws {
        try Self.inDirectory(["Gizmo.swift": Self.commented().file]) { directory in
            let window = ShellWindowLine.Window(path: "Gizmo.swift", statement: "head -c 900 Gizmo.swift", window: LineWindow(stages: [["head", "-c", "900", "Gizmo.swift"]]), numbers: ShellWindowLine.Numbers.none)
            let line = ShellWindowLine(legs: [.window(window)])
            #expect(ShellWindowFold.answer(line, in: directory) { _ in false } == .letThrough(rule: "notExact"))
        }
    }

    @Test("A line of two windows and an echo is answered with both calls and the echo in place")
    func twoWindowsAndAnEcho() throws {
        let first = Self.commented("Widget")
        let second = Self.commented("Gizmo")
        try Self.inDirectory(["A.swift": first.file, "B.swift": second.file]) { directory in
            let outcome = Self.answer("sed -n 1,56p A.swift; echo ---; sed -n 1,56p B.swift", in: directory)
            guard case let .answered(text, calls, source, served) = outcome else {
                Issue.record("expected an answer, got \(outcome)")
                return
            }
            #expect(calls == ["window A.swift:1-56", "window B.swift:1-56"])
            #expect(source == first.file.utf8.count + 4 + second.file.utf8.count)
            #expect(served == text.utf8.count)
            #expect(text.hasSuffix("\n" + first.folded + "---\n" + second.folded))
            let head = "\(ProductName.current.binary) answered `window A.swift:1-56`, `window B.swift:1-56` instead of running it: 96 comment lines in 16 runs folded; the identical command re-run prints them. "
            let opening = try #require(text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first)
            #expect(opening.hasPrefix(head))
            #expect(opening == head + InPlaceAnswer.closingLine(source: source, served: served, standsIn: ""))
            #expect(InPlaceAnswer.calls(inOpeningLine: opening) == calls)
        }
    }

    @Test("An existing opening line still reads as before")
    func existingOpeningLinesStillParse() {
        let line = InPlaceAnswer.openingLine(calls: ["digest Gizmo.swift"])

        #expect(InPlaceAnswer.calls(inOpeningLine: line) == ["digest Gizmo.swift"])
        #expect(InPlaceAnswer.calls(inOpeningLine: "answered `window Gizmo.swift:1-5` instead of running it: and so on") == nil)
    }
}
