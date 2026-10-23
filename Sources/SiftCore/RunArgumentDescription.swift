//
// Copyright © Agulhas Labs
//

import Foundation

/// Holds the physical lines of a Swift Testing event whose printed arguments break across lines, and hands the event on as one line once the sentence that ends it arrives.
///
/// Swift Testing prints a parameterised test's arguments as they are, quotes, backslashes and newlines unescaped: `◇ Test case passing 1 argument text → "one " quote" to stringQuote(_:) started.`, and a value holding newlines lands at the start of the physical lines that follow, so a value that quotes a run's closing sentence (`Executed 5 tests, with 0 failures`, `✔ Test run with 4 tests passed`) makes lines that read exactly like the run's own. Quotes say nothing about where the value ends; the sentence the framework prints after it does.
///
/// A case event (`Test case passing N argument(s) …`, started, passed or failed) ends at ` to <name> started.`, ` to <name> passed after …` or ` to <name> failed after …`, where `<name>` is a test the log has already started (the function's own `Test <name> started.` comes first) and `--verbose` puts the value's type in brackets before ` to`. An issue that names its arguments (`Test f(_:) recorded an issue with 1 argument text → …`) ends at the ` at File.swift:10:9:` of its location. The lines from the opening one to its ending are handed on as one, joined by an escaped `\n` the way the source spelled the break; a log that ends before the ending arrives gets them back from ``release(started:)``, the opening line as printed and the lines after it read again, so a description that never closes hides nothing and holds back no event after it.
struct RunArgumentDescription {
    /// The lines of the event being held, its opening line first; empty when none is open.
    private var held: [String] = []
    /// Whether the event being held is an issue, which ends at its location, rather than a case, which ends at its test's name.
    private var holdsIssue = false

    /// Reads `line` and returns what the readers see now: nothing while an event is held, the event joined into one line at its ending, or `line` itself.
    mutating func read(_ line: String, started: Set<String>) -> [String] {
        if !held.isEmpty {
            held.append(line)
            guard holdsIssue ? Self.locates(Substring(line)) : Self.endsCase(line, started: started) else {
                return []
            }
            defer { held = [] }
            return [held.joined(separator: #"\n"#)]
        }
        guard RunOutputFilter.opensAnEvent(line) else {
            return [line]
        }
        let event = RunOutputFilter.undecorated(line)
        if event.hasPrefix("Test case passing "), !Self.endsCase(line, started: started) {
            held = [line]
            holdsIssue = false
            return []
        }
        if event.hasPrefix("Test "), let arguments = event.firstMatch(of: Self.issueArguments), !Self.locates(event[arguments.range.upperBound...]) {
            held = [line]
            holdsIssue = true
            return []
        }
        return [line]
    }

    /// What the readers see of the lines still held when the log ends, in the order they were read.
    ///
    /// The held event's opening line is handed on as it was printed, and the lines after it are read again from the second, with `started`, so an event among them that opens and ends is joined as it would have been; whatever that holds in turn is released the same way. Each pass hands on at least one line, so it ends, and no line is lost.
    mutating func release(started: Set<String>) -> [String] {
        var released: [String] = []
        while let opening = held.first {
            let rest = held.dropFirst()
            held = []
            released.append(opening)
            for line in rest {
                released += read(line, started: started)
            }
        }
        return released
    }

    /// The words that open an issue's arguments: ` recorded an issue with 2 arguments `, or the known-issue form.
    private static var issueArguments: Regex<Substring> {
        #/ recorded an? (?:known )?issue with \d+ arguments? /#
    }

    /// Whether `text` carries the ` at File.swift:10:9:` that ends an issue's arguments.
    private static func locates(_ text: Substring) -> Bool {
        RunOutputFilter.locationBoundary(in: text) != nil
    }

    /// Whether `line` ends a case event: ` to `, a started test's name (a display name followed, under `--verbose`, by its ` (aka '…')`), then `started.` or `passed after …` or `failed after …`.
    private static func endsCase(_ line: String, started: Set<String>) -> Bool {
        let isStarted = { (name: Substring) in started.contains(RunTestOutcomes.droppingAlias(String(name))) }
        var searchFrom = line.startIndex
        while let candidate = line.range(of: " to ", range: searchFrom ..< line.endIndex) {
            let rest = line[candidate.upperBound...]
            if rest.hasSuffix(" started."), isStarted(rest.dropLast(" started.".count)) {
                return true
            }
            for ending in [" passed after ", " failed after "] {
                if let end = rest.range(of: ending), isStarted(rest[..<end.lowerBound]) {
                    return true
                }
            }
            searchFrom = candidate.upperBound
        }
        return false
    }
}
