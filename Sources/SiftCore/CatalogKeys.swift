//
// Copyright © Agulhas Labs
//

import Foundation

/// The top-level keys of a string catalog (`.xcstrings`, `.strings`, `.stringsdict`) that write a name, as the lines they stand on.
///
/// A byte scanner per format that tracks quoting, escapes and nesting depth (or, for `.strings`, comments), since `JSONSerialization` and `PropertyListSerialization` return keys without their lines. Only keys are read, never values, comments or nested keys. A file is transcoded to UTF-8 before the name's bytes are searched for, and only a file holding them is lexed.
struct CatalogKeys {
    /// The lines of `data`'s top-level keys that write `name`, ascending, one per line and a match where any key on it is; `nil` for a file that is not read: a binary property list, or one that cannot be decoded.
    static func lines(in data: Data, path: String, name: String) -> [NonCodeMentions.Line]? {
        guard let bytes = utf8Bytes(of: data) else { return nil }
        let needle = Array(name.utf8)
        guard !needle.isEmpty else { return [] }
        let skipsAbsentKeys = readsOnlyAsWritten(needle)
        guard !skipsAbsentKeys || contains(needle, in: bytes) else { return [] }
        var byLine: [Int: Bool] = [:]
        for key in keys(of: bytes, path: path) {
            guard !skipsAbsentKeys || contains(needle, in: key.bytes), let verdict = verdict(of: key.text, name: name) else { continue }
            byLine[key.line] = (byLine[key.line] ?? true) && verdict == .lead
        }
        return byLine.keys.sorted().map { NonCodeMentions.Line(number: $0, kind: .catalogKey, isLead: byLine[$0] ?? false) }
    }

    // MARK: Reading

    /// `data` as UTF-8 bytes with any byte-order mark dropped and a UTF-16 file transcoded; `nil` for a binary property list or what is not text in its encoding.
    private static func utf8Bytes(of data: Data) -> [UInt8]? {
        let raw = [UInt8](data)
        if raw.starts(with: Array("bplist".utf8)) {
            return nil
        }
        if raw.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian).map { Array($0.utf8) }
        }
        if raw.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian).map { Array($0.utf8) }
        }
        let body = raw.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(raw.dropFirst(3)) : raw
        return String(bytes: body, encoding: .utf8) == nil ? nil : body
    }

    /// Whether a byte search for `needle` can stand in for judging every key: only an ASCII name, since a catalog may write a non-ASCII name as an escape, or in another canonical form, that no byte search finds (an ASCII name written with escapes of its own letters is not found either).
    private static func readsOnlyAsWritten(_ needle: [UInt8]) -> Bool {
        needle.allSatisfy { $0 < 0x80 }
    }

    private static func contains(_ needle: [UInt8], in bytes: [UInt8]) -> Bool {
        guard needle.count <= bytes.count else { return false }
        let first = needle[0]
        var index = 0
        while index <= bytes.count - needle.count {
            if bytes[index] == first, bytes[index ..< index + needle.count].elementsEqual(needle) {
                return true
            }
            index += 1
        }
        return false
    }

    private static func keys(of bytes: [UInt8], path: String) -> [Key] {
        if path.hasSuffix(".xcstrings") {
            return jsonKeys(in: bytes)
        }
        if path.hasSuffix(".stringsdict") || readsAsXML(bytes) {
            return plistKeys(in: bytes)
        }
        return stringsKeys(in: bytes)
    }

    /// Whether the first bytes after any whitespace are `<?xml` or `<plist`: a `.strings` file written as an XML property list.
    private static func readsAsXML(_ bytes: [UInt8]) -> Bool {
        let rest = bytes.drop { isSpace($0) }
        return rest.starts(with: Array("<?xml".utf8)) || rest.starts(with: Array("<plist".utf8))
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func key(_ raw: [UInt8], line: Int) -> Key {
        Key(bytes: raw, line: line)
    }

    // MARK: Judging

    /// How the key writes `name`: a match if any occurrence is one, else a lead if any is, else `nil`.
    private static func verdict(of text: [Character], name: String) -> Verdict? {
        let needle = Array(name)
        guard let first = needle.first, needle.count <= text.count else { return nil }
        var result: Verdict?
        for start in 0 ... (text.count - needle.count) where Array(text[start ..< start + needle.count]) == needle {
            let end = start + needle.count
            if start > 0, text[start - 1].isWhitespace {
                continue
            }
            if end < text.count, text[end].isWhitespace {
                continue
            }
            guard NonCodeMentions.standsAsCamelCaseWords(needle, in: text, at: start) else { continue }
            let separatedBefore = start == 0 || isSeparator(text[start - 1])
            let separatedAfter = end == text.count || isSeparator(text[end])
            guard separatedBefore, separatedAfter else {
                result = result ?? .lead
                continue
            }
            if !first.isLowercase || (start == 0 && end == text.count) || componentBeforeOpensUppercase(text, start: start) {
                return .match
            }
            result = result ?? .lead
        }
        return result
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "." || character == "_"
    }

    /// Whether the component just before the name, between the previous `.` or `_` and the one before the name, starts uppercase.
    private static func componentBeforeOpensUppercase(_ text: [Character], start: Int) -> Bool {
        guard start >= 2 else { return false }
        var begin = start - 1
        while begin > 0, !isSeparator(text[begin - 1]) {
            begin -= 1
        }
        return begin < start - 1 && text[begin].isUppercase
    }

    // MARK: Escapes

    /// The bytes of a quoted string's body starting after its opening quote at `index`, escapes resolved, and the index past the closing quote.
    private static func quoted(in bytes: [UInt8], from index: Int, lines: inout Int) -> (body: [UInt8], next: Int) {
        var body: [UInt8] = []
        var cursor = index
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == 0x22 {
                return (body, cursor + 1)
            }
            if byte == 0x0A {
                lines += 1
            }
            guard byte == 0x5C, cursor + 1 < bytes.count else {
                body.append(byte)
                cursor += 1
                continue
            }
            let escaped = bytes[cursor + 1]
            cursor += 2
            switch escaped {
            case UInt8(ascii: "n"): body.append(0x0A)
            case UInt8(ascii: "t"): body.append(0x09)
            case UInt8(ascii: "r"): body.append(0x0D)
            case UInt8(ascii: "u"), UInt8(ascii: "U"):
                if let value = hexValue(in: bytes, at: cursor) {
                    cursor += 4
                    if (0xD800 ... 0xDBFF).contains(value) {
                        if let low = lowSurrogate(in: bytes, at: cursor) {
                            body += utf8(of: 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00))
                            cursor += 6
                        } else {
                            body += utf8(of: 0xFFFD)
                        }
                    } else if (0xDC00 ... 0xDFFF).contains(value) {
                        body += utf8(of: 0xFFFD)
                    } else {
                        body += utf8(of: value)
                    }
                } else {
                    body.append(escaped)
                }
            default:
                if escaped == 0x0A {
                    lines += 1
                }
                body.append(escaped)
            }
        }
        return (body, cursor)
    }

    // MARK: JSON (.xcstrings)

    /// The keys of the root object's `strings` object: a string followed by `:` while the containers open are exactly the root and that object.
    private static func jsonKeys(in bytes: [UInt8]) -> [Key] {
        var found: [Key] = []
        var stack: [UInt8] = []
        var line = 1
        var stringsArmed = false
        var stringsDepth: Int?
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x0A:
                line += 1
                index += 1
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                if byte == UInt8(ascii: "{"), stringsArmed, stack.count == 1 {
                    stringsDepth = 2
                }
                stringsArmed = false
                stack.append(byte)
                index += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if stack.count == stringsDepth {
                    stringsDepth = nil
                }
                if !stack.isEmpty {
                    stack.removeLast()
                }
                index += 1
            case 0x22:
                let openLine = line
                let (body, next) = quoted(in: bytes, from: index + 1, lines: &line)
                index = next
                var peek = index
                while peek < bytes.count, isSpace(bytes[peek]) {
                    peek += 1
                }
                let isKey = peek < bytes.count && bytes[peek] == UInt8(ascii: ":") && stack.last == UInt8(ascii: "{")
                if isKey, stack.count == 1 {
                    stringsArmed = body == Array("strings".utf8)
                } else if isKey, stack.count == 2, stringsDepth == 2 {
                    found.append(key(body, line: openLine))
                } else if !isKey {
                    stringsArmed = false
                }
            default:
                index += 1
            }
        }
        return found
    }

    // MARK: Old-style (.strings)

    /// Each entry's key, quoted or bare, before its `=`, outside `/* */` and `//` comments.
    private static func stringsKeys(in bytes: [UInt8]) -> [Key] {
        var found: [Key] = []
        var line = 1
        var index = 0
        // Moves past whitespace and comments.
        func skipTrivia() {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x0A {
                    line += 1
                    index += 1
                } else if isSpace(byte) {
                    index += 1
                } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                    index += 2
                    while index < bytes.count, !(bytes[index] == UInt8(ascii: "*") && index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/")) {
                        if bytes[index] == 0x0A {
                            line += 1
                        }
                        index += 1
                    }
                    index = min(bytes.count, index + 2)
                } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                    while index < bytes.count, bytes[index] != 0x0A {
                        index += 1
                    }
                } else {
                    return
                }
            }
        }
        // Reads one quoted or bare token at `index`.
        func token() -> [UInt8] {
            if bytes[index] == 0x22 {
                let (body, next) = quoted(in: bytes, from: index + 1, lines: &line)
                index = next
                return body
            }
            let begin = index
            while index < bytes.count, !isSpace(bytes[index]), bytes[index] != UInt8(ascii: "="), bytes[index] != UInt8(ascii: ";") {
                index += 1
            }
            return Array(bytes[begin ..< index])
        }
        // Moves past a `{ }` or `( )` value to its matching closer, listing nothing inside.
        func skipNested() {
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index = quoted(in: bytes, from: index + 1, lines: &line).next
                    continue
                }
                if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                    skipTrivia()
                    continue
                }
                index += 1
                switch byte {
                case 0x0A: line += 1
                case UInt8(ascii: "{"), UInt8(ascii: "("): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: ")"):
                    depth -= 1
                    if depth <= 0 {
                        return
                    }
                default: break
                }
            }
        }
        while index < bytes.count {
            skipTrivia()
            guard index < bytes.count else { break }
            if bytes[index] == UInt8(ascii: ";") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "=") {
                index += 1
                continue
            }
            let openLine = line
            let name = token()
            skipTrivia()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else {
                if index < bytes.count, bytes[index] != UInt8(ascii: ";") {
                    index += 1
                }
                continue
            }
            found.append(key(name, line: openLine))
            index += 1
            skipTrivia()
            if index < bytes.count, bytes[index] == UInt8(ascii: "{") || bytes[index] == UInt8(ascii: "(") {
                skipNested()
            } else if index < bytes.count, bytes[index] != UInt8(ascii: ";") {
                _ = token()
            }
        }
        return found
    }

    // MARK: XML property list (.stringsdict)

    /// The `<key>`s directly inside the root `<dict>`.
    private static func plistKeys(in bytes: [UInt8]) -> [Key] {
        var found: [Key] = []
        var line = 1
        var depth = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A {
                line += 1
            }
            guard byte == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            let tagLine = line
            if let skipped = skippedMarkup(in: bytes, at: index, lines: &line) {
                index = skipped
                continue
            }
            guard let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) else { break }
            let tag = bytes[(index + 1) ..< close]
            let isClosing = tag.first == UInt8(ascii: "/")
            let isSelfClosing = tag.last == UInt8(ascii: "/")
            let nameBytes = tag.drop { $0 == UInt8(ascii: "/") }.prefix { !isSpace($0) && $0 != UInt8(ascii: "/") }
            let tagName = (String(bytes: nameBytes, encoding: .utf8) ?? "")
            line += bytes[index ..< close].count { $0 == 0x0A }
            index = close + 1
            switch tagName {
            case "dict", "array":
                if isClosing {
                    depth -= 1
                } else if !isSelfClosing {
                    depth += 1
                }
            case "key" where !isClosing && !isSelfClosing && depth == 1:
                let end = findClosingKey(in: bytes, from: index)
                found.append(key(decodedEntities(Array(bytes[index ..< end])), line: tagLine))
                line += bytes[index ..< end].count { $0 == 0x0A }
                index = end
            default:
                break
            }
        }
        return found
    }

    /// The index past a comment, processing instruction, doctype or CDATA section starting at `index`, or `nil` where `index` starts none.
    private static func skippedMarkup(in bytes: [UInt8], at index: Int, lines: inout Int) -> Int? {
        let terminators: [(opener: String, closer: String)] = [("<!--", "-->"), ("<?", "?>"), ("<![CDATA[", "]]>"), ("<!", ">")]
        for (opener, closer) in terminators where bytes[index...].starts(with: Array(opener.utf8)) {
            let closerBytes = Array(closer.utf8)
            var cursor = index + opener.utf8.count
            while cursor < bytes.count, !bytes[cursor...].starts(with: closerBytes) {
                if bytes[cursor] == 0x0A {
                    lines += 1
                }
                cursor += 1
            }
            return min(bytes.count, cursor + closerBytes.count)
        }
        return nil
    }

    /// Where the `</key>` that ends a key whose text starts at `index` begins, or the end of `bytes`.
    private static func findClosingKey(in bytes: [UInt8], from index: Int) -> Int {
        let closer = Array("</key>".utf8)
        var cursor = index
        while cursor < bytes.count, !bytes[cursor...].starts(with: closer) {
            cursor += 1
        }
        return cursor
    }

    /// The text with the five named entities and numeric character references (`&#N;`, `&#xH;`) decoded in one left-to-right pass, so a decoded `&` is never read as the start of another entity; anything else keeps its `&`.
    private static func decodedEntities(_ raw: [UInt8]) -> [UInt8] {
        guard raw.contains(UInt8(ascii: "&")) else { return raw }
        let named: [(entity: String, text: String)] = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")]
        let text = Array(String(bytes: raw, encoding: .utf8) ?? "")
        var result = ""
        var index = 0
        while index < text.count {
            guard text[index] == "&" else {
                result.append(text[index])
                index += 1
                continue
            }
            let end = text[index...].firstIndex(of: ";").map { $0 + 1 } ?? text.count
            let rest = String(text[index ..< end])
            if let hit = named.first(where: { rest.hasPrefix($0.entity) }) {
                result += hit.text
                index += hit.entity.count
            } else if let (scalar, length) = numericReference(in: rest) {
                result.unicodeScalars.append(scalar)
                index += length
            } else {
                result.append("&")
                index += 1
            }
        }
        return Array(result.utf8)
    }
}

private extension CatalogKeys {
    /// The value of the four hex digits at `index`, or `nil` where they are not four hex digits.
    static func hexValue(in bytes: [UInt8], at index: Int) -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        return UInt32(String(bytes: bytes[index ..< index + 4], encoding: .utf8) ?? "", radix: 16)
    }

    static func utf8(of value: UInt32) -> [UInt8] {
        Array(String(Character(Unicode.Scalar(value) ?? "\u{FFFD}")).utf8)
    }

    /// The value of the low surrogate escape (`\u` or `\U` and four hex digits) at `index`, or `nil` where there is none.
    static func lowSurrogate(in bytes: [UInt8], at index: Int) -> UInt32? {
        guard index + 6 <= bytes.count, bytes[index] == 0x5C, bytes[index + 1] == UInt8(ascii: "u") || bytes[index + 1] == UInt8(ascii: "U"),
              let low = hexValue(in: bytes, at: index + 2), (0xDC00 ... 0xDFFF).contains(low) else { return nil }
        return low
    }

    /// The scalar and length of the numeric character reference that starts `text`, or `nil` where it is not a valid one.
    static func numericReference(in text: String) -> (Unicode.Scalar, Int)? {
        guard text.hasPrefix("&#"), let semicolon = text.firstIndex(of: ";") else { return nil }
        var digits = String(text[text.index(text.startIndex, offsetBy: 2) ..< semicolon])
        var radix = 10
        if digits.hasPrefix("x") {
            digits.removeFirst()
            radix = 16
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(value) else { return nil }
        return (scalar, text.distance(from: text.startIndex, to: semicolon) + 1)
    }

    /// One top-level key's decoded bytes and the 1-based line it stands on.
    struct Key {
        let bytes: [UInt8]
        let line: Int

        /// The key's characters, built only for a key whose bytes hold the name.
        var text: [Character] {
            Array(String(bytes: bytes, encoding: .utf8) ?? "")
        }
    }

    /// How a key writes the name, when it does.
    enum Verdict { case match, lead }
}
