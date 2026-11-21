//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore
@testable import SiftMCP
import Testing

@Suite("A shell line read leg by leg for the comment fold")
struct ShellWindowLineTests {
    static let text = (1 ... 40).map { "let v\($0) = \($0)" }.joined(separator: "\n") + "\n"

    static func window(_ command: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> ShellWindowLine.Window {
        let line = try #require(ShellWindowLine.reading(command), sourceLocation: sourceLocation)
        #expect(line.legs.count == 1, sourceLocation: sourceLocation)
        return try #require(line.windows.first, sourceLocation: sourceLocation)
    }

    @Test("Each window form reads its lines and the numbering its command prints")
    func formsReadTheirNumbering() throws {
        let cases: [(command: String, printed: (ClosedRange<Int>, WindowNumbering))] = [
            ("sed -n 5,9p Gizmo.swift", (5 ... 9, .none)),
            ("cat -n Gizmo.swift | sed -n 5,9p", (5 ... 9, .catN(first: 5))),
            ("sed -n 5,9p Gizmo.swift | cat -n", (5 ... 9, .catN(first: 1))),
            ("sed -n 5,9p Gizmo.swift | nl", (5 ... 9, .numberLines(first: 1, numbersBlank: false))),
            ("sed -n 5,9p Gizmo.swift | nl -ba", (5 ... 9, .numberLines(first: 1, numbersBlank: true))),
            ("sed -n 5,9p Gizmo.swift | awk '{print NR+4\": \"$0}'", (5 ... 9, .awk(first: 5, separator: ": "))),
            ("awk 'NR>=5&&NR<=9{print NR\": \"$0}' Gizmo.swift", (5 ... 9, .awk(first: 5, separator: ": "))),
            ("awk 'NR>=5&&NR<=9' Gizmo.swift", (5 ... 9, .none)),
            ("head -12 Gizmo.swift | tail -3", (10 ... 12, .none)),
        ]
        for (command, (lines, numbering)) in cases {
            let printed = try #require(try Self.window(command).printed(of: Self.text), "\(command)")
            #expect(printed.lines == lines, "\(command)")
            #expect(printed.numbering == numbering, "\(command)")
        }
    }

    @Test("A numbering stage is display: the window is the stages in front of it")
    func numberingStageIsNotAFilter() throws {
        let window = try Self.window("sed -n 160,230p Gizmo.swift | awk '{print NR+159\": \"$0}'")

        #expect(window.window.stages == [["sed", "-n", "160,230p", "Gizmo.swift"]])
        #expect(window.path == "Gizmo.swift")
    }

    @Test("A window whose lines or numbering cannot be read off the command is not rendered")
    func unreadableWindowsAreNotRendered() {
        for command in [
            "head -c 40 Gizmo.swift",
            "cat -n Gizmo.swift | sed -n 5,9p | cat -n",
            "awk 'NR>=5&&NR<=9{print $1}' Gizmo.swift",
            "sed -n '1,3p;8,9p' Gizmo.swift",
        ] {
            let line = ShellWindowLine.reading(command)
            let printed = line?.windows.first?.printed(of: Self.text)
            #expect(printed == nil, "\(command)")
        }
    }

    @Test("A line of windows and echo legs is all windows; any other leg runs others")
    func legsOfALine() throws {
        let line = try #require(ShellWindowLine.reading("sed -n 1,5p A.swift; echo ---; head -3 B.swift && sed -n 2,4p A.swift"))
        #expect(line.windows.map(\.path) == ["A.swift", "B.swift", "A.swift"])
        #expect(line.legs[1] == .echo("---\n"))
        #expect(!line.runsOthers)
        let mixed = try #require(ShellWindowLine.reading("grep -rn Gizmo Sources; sed -n 30,45p A.swift"))
        #expect(mixed.runsOthers)
        #expect(ShellWindowLine.reading("grep -rn Gizmo Sources") == nil)
        #expect(ShellWindowLine.reading("sed -n 1,5p A.swift || cat B.swift") == nil)
    }

    @Test("A set or export that prints the shell's state is a leg, on a line of windows and beside an answered lookup")
    func printingSetIsALeg() throws {
        for printing in ["set", "set -o", "set +o", "set -eo", "export", "export -p", "export -p X"] {
            let line = try #require(ShellWindowLine.reading("\(printing); sed -n 1,5p A.swift"), "\(printing)")
            #expect(line.runsOthers, "\(printing)")
            let match = try #require(InPlaceShape.match(forShell: "\(printing); grep -n 'func stock3()' A.swift", in: nil), "\(printing)")
            #expect(match.runsOtherStatements, "\(printing)")
        }
        for silent in ["set -e", "set -o pipefail", "set -euo pipefail", "set -- a b", "export X=1", "export X", "unset X"] {
            let line = try #require(ShellWindowLine.reading("\(silent); sed -n 1,5p A.swift"), "\(silent)")
            #expect(!line.runsOthers, "\(silent)")
            let match = try #require(InPlaceShape.match(forShell: "\(silent); grep -n 'func stock3()' A.swift", in: nil), "\(silent)")
            #expect(!match.runsOtherStatements, "\(silent)")
        }
    }

    @Test("Each numbering form exits 0 printing only the numbered lines")
    func numberingFormsExitZero() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shell-window-line-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "a\n\nb\n".write(to: directory.appendingPathComponent("w.swift"), atomically: true, encoding: .utf8)
        let forms: [(String, String)] = [
            ("sed -n 1,3p w.swift | nl", "     1\ta\n      \t\n     2\tb\n"),
            ("sed -n 1,3p w.swift | nl -ba", "     1\ta\n     2\t\n     3\tb\n"),
            ("sed -n 1,3p w.swift | awk '{print NR+6\": \"$0}'", "7: a\n8: \n9: b\n"),
        ]
        for (command, expected) in forms {
            let stages = ShellSyntax.segments(of: command).map { ShellQuery($0).invocation }
            #expect(FallbackProof.isProvenWindow(stages), "\(command)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory
            process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(command)")
            #expect(String(bytes: output, encoding: .utf8) == expected, "\(command)")
        }
    }

    @Test("`nl -ba F` reading the file numbers every line as `cat -n F` does, and the fold renders what it prints")
    func nlBaReadingTheFileIsCatN() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shell-window-nl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "a\n\nb\nc\n"
        try source.write(to: directory.appendingPathComponent("w.swift"), atomically: true, encoding: .utf8)
        let command = "nl -ba w.swift | sed -n 2,4p"
        let stages = ShellSyntax.segments(of: command).map { ShellQuery($0).invocation }
        #expect(FallbackProof.isProvenWindow(stages))
        #expect(!FallbackProof.isProvenWindow(ShellSyntax.segments(of: "nl -v 5 w.swift | sed -n 2,4p").map { ShellQuery($0).invocation }))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nl")
        process.arguments = ["-ba", "w.swift"]
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let real = try #require(String(bytes: output, encoding: .utf8))
        #expect(real == "     1\ta\n     2\t\n     3\tb\n     4\tc\n")

        let window = try Self.window(command)
        let printed = try #require(window.printed(of: source))
        #expect(printed.lines == 2 ... 4)
        let fold = try #require(WindowFold.fold(fileText: source, lines: printed.lines, numbering: printed.numbering, commentLines: LineCommentLines.of(source: source)))
        #expect(fold.text == real.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n"))
    }

    @Test("A bare `nl F` reading the file is a window whose lines are not rendered")
    func bareNlIsNotRendered() throws {
        let window = try Self.window("nl w.swift | sed -n 2,4p")

        #expect(window.printed(of: "a\n\nb\nc\n") == nil)
    }

    @Test("An echo whose words the shell expands, or of a lone dash, is not served as its literal words")
    func expandedEchoIsALeg() throws {
        for expanded in ["echo {a,b}", "echo -", "echo a=b", "echo =ls", "echo [ab]", "echo [x]", "echo a,b}", "echo !x", "echo a#b", "echo café"] {
            let line = try #require(ShellWindowLine.reading("sed -n 1,5p A.swift; \(expanded)"), "\(expanded)")
            #expect(line.legs[1] == .other, "\(expanded)")
            #expect(line.runsOthers, "\(expanded)")
        }
        let literal = ShellWindowLine.reading("sed -n 1,5p A.swift; echo --- a")

        #expect(literal?.legs[1] == .echo("--- a\n"))
    }
}
