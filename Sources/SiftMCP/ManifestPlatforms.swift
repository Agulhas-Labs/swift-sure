//
// Copyright © Agulhas Labs
//

import Foundation

/// The platforms a `Package.swift` declares, read as text: the hook has a second to spend, which a `swift package` call would not keep to.
struct ManifestPlatforms {
    /// The platforms the manifest in `root` declares, in order as written (`iOS`, `macOS`, `macCatalyst`), or `nil` where it declares none, cannot be read or gives them by something other than one bracketed list (a `+` after it, or a second `Package(` call, is not read).
    static func declared(inPackageAt root: URL) -> [String]? {
        guard let text = try? String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8) else { return nil }
        return declared(in: text)
    }

    /// The first platform a manifest declares where `macOS` is not among them, or `nil` where the manifest declares none or declares `macOS`.
    static func firstWithoutMacOS(inPackageAt root: URL) -> String? {
        guard let platforms = declared(inPackageAt: root), !platforms.contains("macOS") else { return nil }
        return platforms.first
    }

    /// The platforms the `platforms:` argument of the `Package(` call in `text` lists, outermost entries only: `.iOS(.v17)` is `iOS`, and a `.when(platforms:)` in a target is not the package's.
    static func declared(in text: String) -> [String]? {
        let code = Array(stripped(text))
        guard let call = find("Package(", in: code, from: 0), find("Package(", in: code, from: call + 1) == nil else { return nil }
        var depth = 0
        var index = call + "Package(".count - 1
        while index < code.count {
            let character = code[index]
            if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth -= 1
                if depth <= 0 {
                    return nil
                }
            } else if depth == 1, character == "p", find("platforms:", in: code, from: index) == index, !isIdentifier(code[index - 1]) {
                return list(in: code, from: index + "platforms:".count)
            }
            index += 1
        }
        return nil
    }

    private static func list(in code: [Character], from start: Int) -> [String]? {
        var index = start
        while index < code.count, code[index].isWhitespace {
            index += 1
        }
        guard index < code.count, code[index] == "[" else { return nil }
        var depth = 0
        var names: [String] = []
        while index < code.count {
            let character = code[index]
            if character == "[" || character == "(" {
                depth += 1
            } else if character == "]" || character == ")" {
                depth -= 1
                if depth == 0 {
                    var after = index + 1
                    while after < code.count, code[after].isWhitespace {
                        after += 1
                    }
                    return after < code.count && code[after] == "+" ? nil : names
                }
            } else if character == ".", depth == 1 {
                var end = index + 1
                while end < code.count, isIdentifier(code[end]) {
                    end += 1
                }
                if end > index + 1 {
                    names.append(String(code[(index + 1) ..< end]))
                }
                index = end
                continue
            }
            index += 1
        }
        return nil
    }

    private static func find(_ needle: String, in code: [Character], from start: Int) -> Int? {
        let wanted = Array(needle)
        guard code.count >= wanted.count, start <= code.count - wanted.count else { return nil }
        for index in start ... (code.count - wanted.count) where Array(code[index ..< index + wanted.count]) == wanted {
            return index
        }
        return nil
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// `text` with comments dropped and the inside of string literals emptied, so a bracket in either does not count.
    private static func stripped(_ text: String) -> String {
        var result = ""
        var iterator = Array(text)[...]
        while let character = iterator.popFirst() {
            if character == "/", iterator.first == "/" {
                while let next = iterator.first, next != "\n" {
                    iterator.removeFirst()
                }
            } else if character == "/", iterator.first == "*" {
                iterator.removeFirst()
                while let next = iterator.popFirst(), !(next == "*" && iterator.first == "/") {}
                iterator.removeFirst(iterator.isEmpty ? 0 : 1)
            } else if character == "\"" {
                result.append(character)
                while let next = iterator.popFirst(), next != "\"" {
                    if next == "\\" {
                        iterator.removeFirst(iterator.isEmpty ? 0 : 1)
                    }
                }
                result.append("\"")
            } else {
                result.append(character)
            }
        }
        return result
    }
}
