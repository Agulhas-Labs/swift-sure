//
// Copyright © Agulhas Labs
//

import Foundation

/// A long message or value a listing has already printed, said once: the same message across tests, and a long value repeated within one test.
///
/// It applies only to a failure that has a location and was not read from the event stream, and only after ``RunListingFolds``'s own rules. See Design.md, "A long message or value is said once across the listing".
extension RunListingFolds {
    /// Sets `messageLine` on the folds of the failures `listed` lists, where one of the two rules applies.
    static func foldLongMessages(_ failures: [RunFailureShape.Failure], listed: [Int], folds: inout [Int: Fold], placedAt: (Int) -> String?) {
        var printed: [PrintedMessage] = []
        var folded: Set<Int> = []
        for (index, position) in listed.enumerated() {
            let failure = failures[position]
            guard failure.location != nil, !failure.readFromStream, placedAt(position) != nil else {
                continue
            }
            let line = messageLine(of: failure)
            let masked = MaskedMessage(line)
            if line.utf8.count > RunFailureCensus.wordsCap,
               let target = printed.last(where: { named($0.index, $0.position, at: index, in: failures, listed: listed, placedAt: placedAt) && $0.masked.text == masked.text })
            {
                let clause = masked.clause(differingFrom: target.masked)
                let place = placedAt(target.position) ?? ""
                folds[position, default: Fold()].messageLine = "(the same message line as under \(failures[target.position].name) at \(place) above\(clause))"
                folded.insert(position)
                continue
            }
            printed.append(PrintedMessage(index: index, position: position, masked: masked))
        }
        var earlier: [PrintedPieces] = []
        for (index, position) in listed.enumerated() where !folded.contains(position) {
            let failure = failures[position]
            guard failure.location != nil, !failure.readFromStream, placedAt(position) != nil else {
                continue
            }
            let original = messageLine(of: failure)
            var line = original
            var pieces: Set<String> = []
            for marked in failure.markedLines.dropFirst() {
                let piece = marked.trimmingCharacters(in: .whitespaces)
                guard let arrow = RunFailureShape.firstArrow(in: piece), carries(original, piece) else {
                    continue
                }
                pieces.insert(piece)
                let value = String(piece[arrow.upperBound...])
                guard value.utf8.count > RunFailureCensus.wordsCap else {
                    continue
                }
                let shown = String(piece[..<arrow.lowerBound]) + " → " + head(of: value)
                guard let target = earlier.last(where: { candidate in
                    failures[candidate.position].name == failure.name && candidate.pieces.contains(piece)
                        && named(candidate.index, candidate.position, at: index, in: failures, listed: listed, placedAt: placedAt)
                        && (" " + candidate.line).contains(" " + shown)
                }), let range = range(of: piece, in: line) else {
                    continue
                }
                let place = placedAt(target.position) ?? ""
                let said = String(piece[..<arrow.upperBound]) + "(the value printed under \(failures[target.position].name) at \(place) above)"
                line.replaceSubrange(range, with: said)
            }
            if line != original {
                folds[position, default: Fold()].messageLine = line
            }
            earlier.append(PrintedPieces(index: index, position: position, pieces: pieces, line: RunFailureCensus.clipped(line, to: RunFailureCensus.messageCap)))
        }
    }

    /// The failure's message as the listing prints it under its heading, before the line cap clips it.
    private static func messageLine(of failure: RunFailureShape.Failure) -> String {
        let first = failure.note.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) }
        return first.flatMap { RunFailureShape.merging(failure.message, with: $0) } ?? failure.message
    }

    /// Whether the heading of the failure at `earlier` is a place no failure of its test listed since shows again, so a pointer to it names one place.
    private static func named(_ earlier: Int, _ position: Int, at index: Int, in failures: [RunFailureShape.Failure], listed: [Int], placedAt: (Int) -> String?) -> Bool {
        let place = placedAt(position)
        return !listed[(earlier + 1) ..< index].contains { failures[$0].name == failures[position].name && placedAt($0) == place }
    }

    /// Whether `piece` stands in `line` as one of its space-joined pieces.
    private static func carries(_ line: String, _ piece: String) -> Bool {
        range(of: piece, in: line) != nil
    }

    private static func range(of piece: String, in line: String) -> Range<String.Index>? {
        var from = line.startIndex
        while let found = line.range(of: piece, range: from ..< line.endIndex) {
            let before = found.lowerBound == line.startIndex ? nil : line[line.index(before: found.lowerBound)]
            if before == " ", found.upperBound == line.endIndex || line[found.upperBound] == " " {
                return found
            }
            from = line.index(after: found.lowerBound)
        }
        return nil
    }

    /// The first ``RunFailureCensus/wordsCap`` bytes of `value`, ending on a character boundary, as `clipped` keeps them.
    private static func head(of value: String) -> String {
        var bytes = 0
        return String(value.prefix { character in
            bytes += character.utf8.count
            return bytes <= RunFailureCensus.wordsCap
        })
    }
}

extension RunListingFolds {
    /// A failure whose message line was printed, with the line masked, and where it stands in the listing.
    private struct PrintedMessage {
        let index: Int
        let position: Int
        let masked: MaskedMessage
    }

    /// A failure whose message line was printed, with the pieces it carried and the line as clipped.
    private struct PrintedPieces {
        let index: Int
        let position: Int
        let pieces: Set<String>
        let line: String
    }

    /// A message line with its temporary directories' UUIDs and Foundation object addresses set aside.
    ///
    /// An address is `0x` and 9 to 16 lowercase hex digits only where Foundation prints an object: after `=` and followed by ` {` (`Key=0x… {Error Domain=…}`), or after `: ` inside `<Type: 0x…>` followed by `>` or `;`; any other `0x…` value is compared as text.
    ///
    /// Compared up to a consistent renaming, each kind on its own: the k-th distinct UUID of one message stands for the k-th distinct UUID of another.
    private struct MaskedMessage {
        var text: String
        var uuids: [String] = []
        var addresses: [String] = []

        private static let roots = ["/var/folders/", "/private/var/folders/", "/tmp/", "/private/tmp/"]

        init(_ line: String) {
            var found: [(range: Range<String.Index>, isUUID: Bool)] = []
            for match in line.matches(of: #/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/#)
                where Self.inTemporaryPath(match.range, of: line)
            {
                found.append((match.range, true))
            }
            for match in line.matches(of: #/=(0x[0-9a-f]{9,16}) \{/#) {
                found.append((match.output.1.startIndex ..< match.output.1.endIndex, false))
            }
            for match in line.matches(of: #/<[^<>\s:]+: (0x[0-9a-f]{9,16})(?=[>;])/#) {
                found.append((match.output.1.startIndex ..< match.output.1.endIndex, false))
            }
            found.sort { $0.range.lowerBound < $1.range.lowerBound }
            var rebuilt = ""
            var cursor = line.startIndex
            for item in found where item.range.lowerBound >= cursor {
                rebuilt += line[cursor ..< item.range.lowerBound]
                let value = String(line[item.range])
                if item.isUUID {
                    rebuilt += "‹uuid \(Self.index(of: value, in: &uuids))›"
                } else {
                    rebuilt += "‹address \(Self.index(of: value, in: &addresses))›"
                }
                cursor = item.range.upperBound
            }
            rebuilt += line[cursor...]
            text = rebuilt
        }

        /// `, but for its …` naming only the kinds in which this message's values differ from `other`'s, or nothing where none does.
        func clause(differingFrom other: MaskedMessage) -> String {
            var kinds: [String] = []
            if uuids != other.uuids {
                kinds.append("temporary directories' UUIDs")
            }
            if addresses != other.addresses {
                kinds.append("object addresses")
            }
            return kinds.isEmpty ? "" : ", but for its " + kinds.joined(separator: " and ")
        }

        private static func index(of value: String, in seen: inout [String]) -> Int {
            if let known = seen.firstIndex(of: value) {
                return known
            }
            seen.append(value)
            return seen.count - 1
        }

        /// Whether the path the UUID sits in, read back to the nearest whitespace, `=`, `"` or `,`, runs under a temporary directory.
        private static func inTemporaryPath(_ range: Range<String.Index>, of line: String) -> Bool {
            var start = range.lowerBound
            while start > line.startIndex {
                let before = line.index(before: start)
                if line[before].isWhitespace || "=\",".contains(line[before]) {
                    break
                }
                start = before
            }
            var path = line[start ..< range.lowerBound]
            if path.hasPrefix("file://") {
                path = path.dropFirst("file://".count)
            }
            return roots.contains { path.hasPrefix($0) }
        }
    }
}
