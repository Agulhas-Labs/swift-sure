//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SiftCore
@testable import SiftMCP
import Testing

/// Covers `WindowFold`: the unfolded rendering matches the real command byte for byte for every numbering form, and comment runs fold to the marker line the design names.
@Suite(.serialized, .temporaryDirectories)
struct WindowFoldTests {
    /// Code, blank lines, a CRLF line, a whitespace-only line and a last line with no newline; no comment runs.
    private static var plain: String {
        "import Foundation\n\nstruct Widget {\n    var size = 1\r\n  \n    func grow() {}\n\n}\nlet gizmo = Widget()"
    }

    private static let forms: [Form] = [
        Form(name: "sed", command: { "sed -n \($0),\($1)p w.swift" }, numbering: { _ in .none }),
        Form(name: "cat -n then sed", command: { "cat -n w.swift | sed -n \($0),\($1)p" }, numbering: { .catN(first: $0) }),
        Form(name: "sed then cat -n", command: { "sed -n \($0),\($1)p w.swift | cat -n" }, numbering: { _ in .catN(first: 1) }),
        Form(name: "sed then nl", command: { "sed -n \($0),\($1)p w.swift | nl" }, numbering: { _ in .numberLines(first: 1, numbersBlank: false) }),
        Form(name: "sed then nl -ba", command: { "sed -n \($0),\($1)p w.swift | nl -ba" }, numbering: { _ in .numberLines(first: 1, numbersBlank: true) }),
        Form(
            name: "awk NR",
            command: { "awk 'NR>=\($0)&&NR<=\($1){print NR\": \"$0}' w.swift" },
            numbering: { .awk(first: $0, separator: ": ") }
        ),
        Form(
            name: "sed then awk NR+k",
            command: { "sed -n \($0),\($1)p w.swift | awk '{print NR+\($0 - 1)\": \"$0}'" },
            numbering: { .awk(first: $0, separator: ": ") }
        ),
    ]

    private static func run(_ command: String, in directory: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, sourceLocation: sourceLocation)
        return data
    }

    @Test(arguments: forms.map(\.name))
    func `the unfolded rendering is the command's output byte for byte`(name: String) throws {
        let form = try #require(Self.forms.first { $0.name == name })
        let directory = try TemporaryDirectory.make("window-fold")
        try Self.plain.write(to: directory.appendingPathComponent("w.swift"), atomically: true, encoding: .utf8)
        for window in [(1, 9), (2, 5), (3, 4), (5, 7), (6, 40), (9, 9)] {
            let expected = try Self.run(form.command(window.0, window.1), in: directory)
            let fold = try #require(WindowFold.fold(
                fileText: Self.plain,
                lines: window.0 ... window.1,
                numbering: form.numbering(window.0),
                commentLines: []
            ))
            #expect(Data(fold.text.utf8) == expected, "\(name) \(window)")
            #expect(fold.printedBytes == expected.count, "\(name) \(window)")
            #expect(fold.runs == 0)
        }
    }

    @Test
    func `bare nl prints a blank line as six spaces and a tab and does not count it`() throws {
        let fold = try #require(WindowFold.fold(
            fileText: "a\n\nb\n", lines: 1 ... 3, numbering: .numberLines(first: 1, numbersBlank: false), commentLines: []
        ))

        #expect(fold.text == "     1\ta\n      \t\n     2\tb\n")
    }

    /// Lines 1-12: runs of 3 (2-4), a lone comment (6), a run of 2 (8-9) broken by a blank at 10, a run cut by the window's end (11-12).
    private static let commented = [
        "let a = 1", "// one", "// two", "/// three", "let b = 2", "// lone", "let c = 3",
        "    // four", "\t// five", "", "// six", "// seven", "// eight", "let d = 4",
    ].joined(separator: "\n") + "\n"

    @Test
    func `runs fold to a marker under each numbering`() throws {
        let comments = LineCommentLines.of(source: Self.commented)
        #expect(comments == [2, 3, 4, 6, 8, 9, 11, 12, 13])

        let none = try #require(WindowFold.fold(fileText: Self.commented, lines: 1 ... 12, numbering: .none, commentLines: comments))
        #expect(none.text == "let a = 1\n2-4: // … 3 comment lines\nlet b = 2\n// lone\nlet c = 3\n8-9: // … 2 comment lines\n\n11-12: // … 2 comment lines\n")
        #expect(none.foldedLines == 7)
        #expect(none.runs == 3)

        let cat = try #require(WindowFold.fold(fileText: Self.commented, lines: 3 ... 12, numbering: .catN(first: 1), commentLines: comments))
        #expect(cat.text == "1-2: // … 2 comment lines\n     3\tlet b = 2\n     4\t// lone\n     5\tlet c = 3\n6-7: // … 2 comment lines\n     8\t\n9-10: // … 2 comment lines\n")

        let awk = try #require(WindowFold.fold(
            fileText: Self.commented, lines: 4 ... 11, numbering: .awk(first: 4, separator: ": "), commentLines: comments
        ))
        #expect(awk.text == "4: /// three\n5: let b = 2\n6: // lone\n7: let c = 3\n8-9: // … 2 comment lines\n10: \n11: // six\n")
        #expect(awk.runs == 1)
    }

    @Test
    func `a run cut by the window's edge counts only its printed lines`() throws {
        let comments = LineCommentLines.of(source: Self.commented)
        let fold = try #require(WindowFold.fold(fileText: Self.commented, lines: 3 ... 3, numbering: .none, commentLines: comments))
        #expect(fold.text == "// two\n")
        let two = try #require(WindowFold.fold(fileText: Self.commented, lines: 3 ... 4, numbering: .none, commentLines: comments))
        #expect(two.text == "3-4: // … 2 comment lines\n")
    }

    @Test
    func `a section delimiter under nl cannot be rendered`() {
        let text = "a\n\\:\\:\\:\nb\n"

        #expect(WindowFold.fold(fileText: text, lines: 1 ... 3, numbering: .numberLines(first: 1, numbersBlank: false), commentLines: []) == nil)
        #expect(WindowFold.fold(fileText: text, lines: 1 ... 3, numbering: .catN(first: 1), commentLines: []) != nil)
    }

    @Test
    func `a window of forty lines with twelve comment lines in three runs saves the expected bytes`() throws {
        var lines = [String]()
        for index in 1 ... 40 {
            switch index {
            case 5 ... 8, 20 ... 23, 30 ... 33: lines.append("    // Widget note number \(index)")
            default: lines.append("    let gizmo\(index) = \(index)")
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        let comments = LineCommentLines.of(source: text)
        #expect(comments.count == 12)
        let fold = try #require(WindowFold.fold(fileText: text, lines: 1 ... 40, numbering: .catN(first: 1), commentLines: comments))
        #expect(fold.runs == 3)
        #expect(fold.foldedLines == 12)
        var markerBytes = 0
        for (first, last) in [(5, 8), (20, 23), (30, 33)] {
            markerBytes += "\(first)-\(last): // … 4 comment lines\n".utf8.count
        }
        var commentBytes = 0
        for number in comments {
            commentBytes += 7 + lines[number - 1].utf8.count + 1
        }
        #expect(fold.printedBytes - fold.text.utf8.count == commentBytes - markerBytes)
    }
}

extension WindowFoldTests {
    private struct Form: Sendable {
        let name: String
        let command: @Sendable (_ first: Int, _ last: Int) -> String
        let numbering: @Sendable (_ first: Int) -> WindowNumbering
    }
}
