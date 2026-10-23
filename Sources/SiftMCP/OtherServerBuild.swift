//
// Copyright © Agulhas Labs
//

import Foundation
import SiftCore

/// A build or test made through another MCP server's tool, as the Stop gate reads one from a transcript: which calls count, which paths they name, and whether a result shows a green build.
///
/// Strict on purpose: a result is read as green only where it carries a build tool's own success line and no failure line anywhere, and as a test run, which a tool named for tests always is, only where it ran tests, since a loose reading takes failed tests for a pass.
struct OtherServerBuild {
    /// The server the call went to, as the tool name spells it.
    let server: String
    /// The tool's own name, the last segment of the call's.
    let tool: String
    /// The absolute paths among the call's input values, at any depth.
    let paths: [String]
    /// Whether a word of the tool's name is `test`: its result is a test run whatever its text shows, so a green one must report tests run.
    let isTest: Bool

    /// The call in `block`, where it is an MCP tool of a server outside `products` whose name reads as a build or a test and not as a reader of one; `nil` otherwise.
    ///
    /// The tool is the name's last `__` segment, split into words on `_`, `-` and changes of case: one word must be `build`, or `test` in one of its forms, whole, and none a reader's word or its plural, since a tool that reads a log, a status or a history can quote an earlier success.
    init?(call block: [String: Any], recognising products: [ProductName]) {
        guard let name = block["name"] as? String, name.hasPrefix(Self.mcpPrefix),
              IndexToolName.tool(named: name, recognising: products) == nil,
              let separator = name.ranges(of: "__").last
        else {
            return nil
        }
        let serverStart = name.index(name.startIndex, offsetBy: Self.mcpPrefix.count)
        guard separator.lowerBound > serverStart else { return nil }
        let words = Set(Self.words(of: String(name[separator.upperBound...])))
        guard !words.isDisjoint(with: Self.actionWords), words.isDisjoint(with: Self.readerWords) else { return nil }
        server = String(name[serverStart ..< separator.lowerBound])
        tool = String(name[separator.upperBound...])
        paths = Self.paths(in: block["input"] ?? [:])
        isTest = !words.isDisjoint(with: Self.testWords)
    }

    /// The directory a named path is asked about for its repository: the path itself where it is a directory, else the one holding it.
    static func directory(of path: String) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return path
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    /// The text of a `tool_result` block: its `content` where that is text, else the text of each of its blocks, one per line, or `nil` where any block is not text, since what the other blocks show cannot be read.
    static func text(ofResult block: [String: Any]) -> String? {
        if let text = block["content"] as? String {
            return text
        }
        var lines: [String] = []
        for part in block["content"] as? [[String: Any]] ?? [] {
            guard part["type"] as? String == "text", let text = part["text"] as? String else { return nil }
            lines.append(text)
        }
        return lines.joined(separator: "\n")
    }

    /// What a call's result text shows, where `testRun` says the call is a test run whatever the text holds.
    ///
    /// A text the harness put aside as too large, and stands in for with a preview of its head, is never green: the lines that decide sit past the preview.
    static func verdict(of text: String, testRun: Bool) -> Verdict {
        guard !text.contains(persistedOutputMarker) else {
            return Verdict(isGreen: false, isSilent: false)
        }
        var successes: [Success] = []
        var failed = false
        for line in text.split(whereSeparator: \.isNewline) {
            if isFailure(line) {
                failed = true
            } else if let success = success(line) {
                successes.append(success)
            }
        }
        let swiftTesting = successes.compactMap {
            if case let .swiftTesting(count) = $0 {
                count
            } else {
                nil
            }
        }.max()
        let xcTest = successes.compactMap {
            if case let .xcTest(count) = $0 {
                count
            } else {
                nil
            }
        }.max()
        // A test line or a test tool makes a test run, which the counts decide: `Build complete!` before a test line, and XCTest's zero line beside a Swift Testing pass, then pass nothing on their own.
        let isTestRun = testRun || successes.contains { $0.isTestLine || $0 == .testSucceeded }
        let ranTests = (swiftTesting ?? 0) + (xcTest ?? 0) > 0
        return Verdict(isGreen: !failed && !successes.isEmpty && (!isTestRun || ranTests), isSilent: !failed && successes.isEmpty)
    }
}

extension OtherServerBuild {
    /// What a result's text shows about the build.
    struct Verdict {
        /// Whether it shows a green build or test: a success line, no failure line anywhere, and tests run where it is a test run.
        let isGreen: Bool
        /// Whether it carries neither a success line nor a failure line: a result that says nothing of how the build went.
        let isSilent: Bool
    }

    /// A success line, by the tool that prints it.
    enum Success: Equatable {
        case buildSucceeded
        case testSucceeded
        /// SwiftPM's `Build complete!`, which `swift test` also prints before its tests run.
        case buildComplete
        /// A Swift Testing pass, with the tests it ran.
        case swiftTesting(Int)
        /// An XCTest summary with no failures, with the tests it ran.
        case xcTest(Int)

        var isTestLine: Bool {
            switch self {
            case .swiftTesting, .xcTest:
                true
            case .buildSucceeded, .testSucceeded, .buildComplete:
                false
            }
        }
    }
}

private extension OtherServerBuild {
    static var mcpPrefix: String {
        "mcp__"
    }

    /// A word any of which marks a tool as a test run, which needs a test count to clear.
    static let testWords: Set = ["test", "tests", "testing"]

    /// A word one of which marks a tool as a build or a test.
    static let actionWords = testWords.union(["build"])

    /// A word any of which marks a tool as one that reads, lists or reports on builds rather than makes one: each reader's word with its plural.
    static let readerWords: Set = [
        "log", "logs", "get", "gets", "read", "reads", "show", "shows", "list", "lists", "result", "results",
        "status", "statuses", "history", "histories", "last", "latest", "previous", "recent",
    ]

    /// The harness's opening tag for a result too large to keep inline, which it replaces with the file it saved and a preview of the head.
    static var persistedOutputMarker: String {
        "<persisted-output>"
    }

    /// `tool` split into lowercase words on `_`, `-` and changes of case, an acronym kept whole before the word it starts (`XCTestRun`: `xc`, `test`, `run`).
    static func words(of tool: String) -> [String] {
        let characters = Array(tool)
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if character == "_" || character == "-" {
                words.append(current)
                current = ""
                continue
            }
            if character.isUppercase, let previous = current.last,
               previous.isLowercase || previous.isNumber || previous.isUppercase && index + 1 < characters.count && characters[index + 1].isLowercase
            {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        words.append(current)
        return words.filter { !$0.isEmpty }.map { $0.lowercased() }
    }

    /// Every absolute path among `value` and the values inside it, a leading `~/` read as the home directory.
    static func paths(in value: Any) -> [String] {
        switch value {
        case let text as String:
            if text.hasPrefix("/") {
                [text]
            } else if text.hasPrefix("~/") {
                [NSString(string: text).expandingTildeInPath]
            } else {
                []
            }
        case let list as [Any]:
            list.flatMap(paths)
        case let object as [String: Any]:
            object.values.flatMap(paths)
        default:
            []
        }
    }

    /// Whether `line` reports a failure: an `xcodebuild` `** … FAILED **`, an `error:`, a Swift Testing run that failed, or an XCTest summary with failures.
    static func isFailure(_ line: Substring) -> Bool {
        if line.contains("error:") || line.firstMatch(of: /\*\* .*FAILED \*\*/) != nil || line.firstMatch(of: /Test run .*failed/) != nil {
            return true
        }
        return line.matches(of: /with (\d+) failures?/).contains { Int($0.output.1).map { $0 > 0 } ?? false }
    }

    /// The success `line` reports, or `nil` where it reports none.
    static func success(_ line: Substring) -> Success? {
        if line.contains("** BUILD SUCCEEDED **") {
            return .buildSucceeded
        }
        if line.contains("** TEST SUCCEEDED **") {
            return .testSucceeded
        }
        if let match = line.firstMatch(of: /Test run with (\d+) tests? .*passed/), let count = Int(match.output.1) {
            return .swiftTesting(count)
        }
        if let match = line.firstMatch(of: /Executed (\d+) tests?, with 0 failures/), let count = Int(match.output.1) {
            return .xcTest(count)
        }
        return line.contains("Build complete!") ? .buildComplete : nil
    }
}
