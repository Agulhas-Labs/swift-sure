//
// Copyright © Agulhas Labs
//

import SwiftParser
import SwiftSyntax

/// The lines of a Swift file that hold nothing but a line comment, as the Swift lexer reads the whole file.
///
/// A `//` line inside a multi-line string literal or a block comment is part of that token, not a comment piece, so it is code here; a line with code before a trailing comment is not a comment line either.
public struct LineCommentLines {
    /// The 1-based line numbers of `source` whose only token is a line comment (`//` or `///`).
    ///
    /// Leading spaces and tabs are allowed. The syntax tree is dropped before the call returns.
    public static func of(source: String) -> Set<Int> {
        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for (offset, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") {
            lineStarts.append(offset + 1)
        }
        var result = Set<Int>()
        let tree = Parser.parse(source: source)
        for token in tree.tokens(viewMode: .sourceAccurate) {
            var offset = token.position.utf8Offset
            for piece in token.leadingTrivia {
                record(piece, at: offset, bytes: bytes, lineStarts: lineStarts, into: &result)
                offset += piece.sourceLength.utf8Length
            }
            offset = token.endPositionBeforeTrailingTrivia.utf8Offset
            for piece in token.trailingTrivia {
                record(piece, at: offset, bytes: bytes, lineStarts: lineStarts, into: &result)
                offset += piece.sourceLength.utf8Length
            }
        }
        return result
    }

    private static func record(
        _ piece: TriviaPiece,
        at offset: Int,
        bytes: [UInt8],
        lineStarts: [Int],
        into result: inout Set<Int>
    ) {
        switch piece {
        case .lineComment, .docLineComment:
            break
        default:
            return
        }
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let onlyBlanksBefore = bytes[lineStarts[low] ..< offset].allSatisfy { $0 == 0x20 || $0 == 0x09 }
        if onlyBlanksBefore {
            result.insert(low + 1)
        }
    }
}
