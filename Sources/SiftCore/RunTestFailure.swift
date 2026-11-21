//
// Copyright © Agulhas Labs
//

import Foundation

/// One failing test, whichever framework reported it.
///
/// Swift Testing and XCTest print nothing alike, but the three things worth keeping are the same in both — which test, where it failed, and what it said — so they are normalised into one shape rather than two.
///
/// Two fields exist only for Swift Testing's parameterized form, where the same function fails several times over: the arguments say *which* case, and the `↳` comment beneath the expectation says what the author expected to see. Dropping either while it sits in the log is the failure mode this type exists to prevent — a failure reported as unexplained next to its own explanation.
public struct RunTestFailure: Sendable {
    public let name: String
    /// The arguments the case failed under, as the framework printed them — `size → .large`; `nil` for a test that takes none.
    public let arguments: String?
    /// The source location as printed, e.g. `WidgetTests.swift:10:9`; `nil` when the framework named none.
    public let location: String?
    public let message: String
    /// The comment printed beneath the failure on its own `↳` line, which is the sentence the expectation was written with; `nil` when it carried none.
    ///
    /// Attributed to this failure by adjacency in the log and by nothing else, which is an approximation: `xcodebuild` interleaves the output of parallel test runners, so a comment printed under a neighbouring test's failure can land here instead. Nothing in the log says otherwise, and this is where that is written down.
    public let note: String?
    /// For a failed `.contains`/`.hasPrefix`/`.hasSuffix`, the haystack line worth reading beside it — see ``RunFailureCensus/closestLine(message:note:truncated:)``; `nil` for any other failure.
    ///
    /// Worked out from the whole of the note as the log printed it, before the note is capped, because the line that answers the question is rarely among the first few the cap keeps.
    public let closestLine: String?
    /// Each `↳` line of ``note`` on its own, in the order the log printed them, a multi-line expression joined into one.
    ///
    /// A line read from the console keeps the depth Swift Testing printed it at, the text after the `↳` less its one separating space, so a subexpression's line opens on two spaces per level beneath the whole expression's; a multi-line expression keeps the depth of its first line. A line from the event stream carries no depth. ``note`` never holds the indentation.
    ///
    /// The note joins these with a space, which is right for reading and loses where one line ended: Swift Testing prints each expansion of an expectation as a `↳` line of its own, `<expression> → <value>`, and only the line it was printed on says where a value ends and the next expression begins. ``RunDominantFailureClass`` reads the values from these.
    public let markedLines: [String]
    /// Whether ``message`` is the event stream's, put in place of a console line the run never relayed, so the entry says where it was read from.
    public let readFromStream: Bool

    public init(name: String, arguments: String? = nil, location: String?, message: String, note: String? = nil, closestLine: String? = nil, markedLines: [String] = [], readFromStream: Bool = false) {
        self.name = name
        self.arguments = arguments
        self.location = location
        self.message = message
        self.note = note
        self.closestLine = closestLine
        self.markedLines = markedLines
        self.readFromStream = readFromStream
    }
}

public extension RunTestFailure {
    /// The same failure carrying the `↳` comment printed directly beneath it, appended to any it already had.
    ///
    /// Appended rather than replacing, because a note runs to as many `↳` lines as its author wrote and the second is as much the sentence as the first: replacing would leave a failure holding the source comment above its expectation and drop the line that says what went wrong. Joined with a space, since the line break is the terminal's and not the author's — except for `apart`, a line the log printed on a line of its own beneath the `↳` (an indented list entry), which keeps its break so a short list is read as the list it is. Each line is bounded by ``RunFailureCensus/wordsCap`` when it is rendered, the same as a message.
    ///
    /// A line that is not `apart` is a `↳` line of its own, so it is also kept whole in ``markedLines``, behind the `indent` the log printed it at; the note itself never carries it.
    func noting(_ note: String, apart: Bool = false, indent: String = "") -> RunTestFailure {
        let joined = self.note.map { "\($0)\(apart ? "\n" : " ")\(note)" } ?? note
        let marked = apart ? markedLines : markedLines + [indent + note]
        return RunTestFailure(name: name, arguments: arguments, location: location, message: message, note: joined, closestLine: closestLine, markedLines: marked, readFromStream: readFromStream)
    }

    /// The failure of an expectation once its whole `note` is held: carrying its closest line, and its note rebuilt where ``RunFailureCensus/droppingEchoes(message:note:)`` drops anything or ``RunFailureCensus/compactedHaystack(message:note:truncated:)`` compacts what is left, with how many lines past `cap` the rebuilt note left out (`nil` where the note streamed in stands).
    ///
    /// The rebuilt note joins its lines as ``noting(_:apart:indent:)`` does — a `↳` line to the one above by a space, an unmarked line on its own line, held blanks left out — and keeps `cap` of them. A failure read from the event stream is never rebuilt.
    func closingNote(note: [RunFailureCensus.NoteLine], truncated: Bool, cap: Int) -> (failure: RunTestFailure, elided: Int?) {
        let closest = RunFailureCensus.closestLine(message: message, note: note, truncated: truncated)
        let found = closest.map { withClosestLine($0) } ?? self
        guard !readFromStream else {
            return (found, nil)
        }
        let held = truncated ? note : RunFailureCensus.droppingEchoes(message: message, note: note)
        guard let compacted = RunFailureCensus.compactedHaystack(message: message, note: held, truncated: truncated) ?? (held.count == note.count ? nil : held) else {
            return (found, nil)
        }
        let shown = compacted.filter { !$0.text.isEmpty }
        let joined = shown.prefix(cap).reduce(into: String?.none) { joined, line in
            joined = joined.map { "\($0)\(line.marked ? " " : "\n")\(line.text)" } ?? line.text
        }
        return (found.withNote(joined), max(0, shown.count - cap))
    }

    /// The same failure with `note` in place of the one it holds, ``markedLines`` as the log printed them.
    func withNote(_ note: String?) -> RunTestFailure {
        RunTestFailure(name: name, arguments: arguments, location: location, message: message, note: note, closestLine: closestLine, markedLines: markedLines, readFromStream: readFromStream)
    }

    /// The same failure carrying `closestLine`.
    func withClosestLine(_ closestLine: String) -> RunTestFailure {
        RunTestFailure(name: name, arguments: arguments, location: location, message: message, note: note, closestLine: closestLine, markedLines: markedLines, readFromStream: readFromStream)
    }
}
