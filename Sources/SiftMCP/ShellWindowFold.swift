//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The answer a line of shell windows gets: what the line prints, read from disk, each run of comment lines folded to one marker line, under one framing line, or the rule that lets the line through.
public struct ShellWindowFold {
    /// The least the fold itself must save, as a share of the bytes the line prints: a quarter.
    public static let foldSavingShare = 0.25
    /// The least the whole denial, framing line included, must be smaller than the bytes the line prints, in UTF-8 bytes.
    public static let foldSavingFloor = 400

    /// The answer for `line`, which holds no leg but windows and `echo`s, read relative to `directory`.
    ///
    /// `rerun` names what the framing line says re-running prints the folded lines: the command, or the tool call the line stands for.
    ///
    /// `parsesWithError` is asked, with a file's absolute path, whether the index holds that file with a parse error.
    public static func answer(_ line: ShellWindowLine, in directory: String?, rerun: String = "command", parsesWithError: (String) -> Bool) -> Outcome {
        guard !line.runsOthers else { return .letThrough(rule: "notExact") }
        var body = ""
        var printed = 0
        var calls = [String]()
        var folded = 0
        var runs = 0
        for leg in line.legs {
            switch leg {
            case let .echo(text):
                body += text
                printed += text.utf8.count
            case let .window(window):
                guard let file = OperandFile.readable(window.path, in: directory),
                      let data = FileManager.default.contents(atPath: file),
                      let text = String(bytes: data, encoding: .utf8)
                else { return .letThrough(rule: "notExact") }
                if let rule = unservable(window, file: file, in: directory, parsesWithError: parsesWithError) {
                    return .letThrough(rule: rule)
                }
                guard let shown = window.printed(of: text),
                      let fold = WindowFold.fold(fileText: text, lines: shown.lines, numbering: shown.numbering, commentLines: LineCommentLines.of(source: text))
                else { return .letThrough(rule: "notExact") }
                body += fold.text
                printed += fold.printedBytes
                folded += fold.foldedLines
                runs += fold.runs
                calls.append("window \(window.path):\(shown.lines.lowerBound)-\(shown.lines.upperBound)")
            case .other:
                return .letThrough(rule: "notExact")
            }
        }
        guard printed > 0, Double(printed - body.utf8.count) / Double(printed) >= foldSavingShare else { return .letThrough(rule: "notSmaller") }
        let head = "\(ProductName.current.binary) answered \(calls.map { "`\($0)`" }.joined(separator: ", ")) instead of running it: \(folded) comment lines in \(runs) runs folded; the identical \(rerun) re-run prints them. "
        let fixed = head.utf8.count + 1 + body.utf8.count
        guard let text = framed(head: head, body: body, fixed: fixed, source: printed) else { return .letThrough(rule: "notSmaller") }
        let served = text.utf8.count
        guard printed - served >= foldSavingFloor else { return .letThrough(rule: "notSmaller") }
        guard served <= InPlaceAnswer.sizeBudget else { return .letThrough(rule: "overSize") }
        return .answered(text: text, calls: calls, source: printed, served: served)
    }

    /// The rule the first window of `line` whose file no answer could serve lets the line through under, read relative to `directory`: `conflicted` for a file holding a conflict marker, `parseError` for one `parsesWithError` holds; `nil` where every window's file could be served.
    ///
    /// It decides before ``InPlaceAnswerer/Withholding/windowBeside``, since such a line is no miss.
    public static func unservable(_ line: ShellWindowLine, in directory: String?, parsesWithError: (String) -> Bool) -> String? {
        for window in line.windows {
            if let file = OperandFile.readable(window.path, in: directory), let rule = unservable(window, file: file, in: directory, parsesWithError: parsesWithError) {
                return rule
            }
        }
        return nil
    }

    /// The rule `window`, whose file is at `file`, lets its line through under before it is weighed, or `nil`.
    private static func unservable(_ window: ShellWindowLine.Window, file: String, in directory: String?, parsesWithError: (String) -> Bool) -> String? {
        if OperandFile.holdsConflictMarkers(window.path, in: directory) {
            return "conflicted"
        }
        return parsesWithError(file) ? "parseError" : nil
    }

    /// Whether the index of the repository holding `file`, an absolute path, holds it with a parse error, read off the stored index without bringing it up to date, so asking costs the hook no indexing.
    public static func indexedWithParseError(_ file: String) -> Bool {
        let canonical = CanonicalPath.of(file)
        guard let root = CallerRoot.root(forCallerIn: (canonical as NSString).deletingLastPathComponent).map(CanonicalPath.of) else { return false }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard canonical.hasPrefix(prefix) else { return false }
        return ReadOnlyIndex.holdsParseErrors(inFile: String(canonical.dropFirst(prefix.count)), atRoot: root)
    }

    /// The denial with the closing sizes written at the one length whose figures are the text's own, or `nil` where there is none.
    ///
    /// The search is the one ``InPlaceAnswer/reason(calls:answer:source:standsIn:wholeCommand:lookups:note:rerun:teed:)`` makes: from the first draft's length outward, nearest first and the shorter of each pair first.
    private static func framed(head: String, body: String, fixed: Int, source: Int) -> String? {
        let start = InPlaceAnswer.closingLine(source: source, served: fixed, standsIn: "").utf8.count
        for offset in 0 ... start {
            for length in offset == 0 ? [start] : [start - offset, start + offset] {
                let closing = InPlaceAnswer.closingLine(source: source, served: fixed + length, standsIn: "")
                if closing.utf8.count == length, source > fixed + length {
                    return head + closing + "\n" + body
                }
            }
        }
        return nil
    }
}

public extension ShellWindowFold {
    enum Outcome: Equatable {
        /// `text` is the whole denial; `source` the bytes the line prints and `served` the denial's own byte count.
        case answered(text: String, calls: [String], source: Int, served: Int)
        /// The line runs; `rule` is the withholding's name: `notSmaller`, `notExact`, `overSize`, `conflicted` or `parseError`.
        case letThrough(rule: String)
    }
}
