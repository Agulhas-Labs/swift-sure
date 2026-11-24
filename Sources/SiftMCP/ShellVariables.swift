//
// Copyright © Agulhas Labs
//

import Foundation

/// The plain assignments a shell line makes for itself, read so that a later word using one is judged by its value.
///
/// Only the one shape the line itself settles: a statement of its own, at the top of the line and reached unconditionally, assigning one literal word with no blank in it, read where the use is at the top of the line too. Anything else that assigns the name, or a value the text does not carry, leaves the name unbound, a line holding anything that can assign without a plain assignment word binds nothing, and a word still holding an expansion is left as written.
///
/// What this expands is read to judge and record a line, never handed back: every command the hook emits is built from the line as written.
public struct ShellVariables {
    /// The line with every top-level use of a name a plain assignment earlier on it binds replaced by the value.
    ///
    /// A use unquoted is single-quoted where the value holds a character the shell would read again; a use inside double quotes keeps the value one word. A use inside a subshell, a group, a substitution, a function body or a compound command is never replaced. A line that binds nothing comes back unchanged.
    public static func expanded(_ command: String) -> String {
        guard command.contains("="), command.contains("$"), !rebindsOtherwise(command) else { return command }
        let statements = ShellSyntax.statementRanges(of: command)
        guard !statements.isEmpty else { return command }
        let joints = InPlaceShape.joints(of: command, between: statements)
        let offset = { (index: String.Index) in command.distance(from: command.startIndex, to: index) }
        var scope = Scope()
        var readings: [Reading] = []
        for (index, (statement, range)) in statements.enumerated() {
            let before = index == 0 ? "" : joints[index - 1]
            let after = index < joints.count ? joints[index] : ""
            let topLevel = scope.isTopLevel
            let runsHere = topLevel && ["", ";", "&"].contains(before) && ["", ";", "&&", "||"].contains(after)
            let opensCompound = ShellSyntax.tokens(of: statement, stripQuotes: false).first.map(Scope.compoundOpeners.contains) ?? false
            readings.append(Reading(
                span: offset(range.lowerBound) ..< offset(range.upperBound),
                substitutes: topLevel && !opensCompound,
                binding: runsHere ? binding(statement) : nil
            ))
            scope.enter(statement)
        }
        guard readings.contains(where: { $0.binding != nil }) else { return command }
        let unbound = unbindings(in: command)
        return substituted(command) { name, position in
            guard let use = readings.firstIndex(where: { $0.span.contains(position) }), readings[use].substitutes,
                  let bound = readings[..<use].lastIndex(where: { $0.binding?.name == name }),
                  let value = readings[bound].binding?.value,
                  !unbound.contains(where: { $0.name == name && $0.offset >= readings[bound].span.upperBound && $0.offset < readings[use].span.upperBound })
            else { return nil }
            return value
        }
    }

    /// The payload and flag with their shell line expanded, so every reader of either sees the same line.
    public static func expanding(payload: [String: Any], command: String?) -> (payload: [String: Any], command: String?) {
        var payload = payload
        if var input = payload["tool_input"] as? [String: Any], let line = input["command"] as? String {
            input["command"] = expanded(line)
            payload["tool_input"] = input
        }
        return (payload, command.map(expanded))
    }

    /// The name and value `statement` binds, where it is one plain assignment word of a literal value.
    static func binding(_ statement: String) -> (name: String, value: String)? {
        let word = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShellSyntax.tokens(of: word, stripQuotes: false) == [word],
              let equals = word.firstIndex(of: "="),
              isName(word[..<equals])
        else {
            return nil
        }
        return literalValue(of: word[word.index(after: equals)...]).map { (String(word[..<equals]), $0) }
    }

    /// The value the shell stores for an assignment's written value, or nil where it is not one literal word free of blanks.
    ///
    /// A blank, even quoted, binds nothing: bash splits an unquoted use of such a value and zsh does not, so no one reading of the use is right for both.
    static func literalValue(of written: Substring) -> String? {
        let characters = Array(written)
        var value = ""
        var quote: Character?
        for (offset, character) in characters.enumerated() {
            if character == "$" || character == "`" || character == "\\" || "*?[".contains(character) || character.isWhitespace {
                return nil
            }
            if character == "~", !value.isEmpty || offset + 1 >= characters.count || characters[offset + 1] != "/" {
                return nil
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    value.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if ";&|<>()".contains(character) {
                return nil
            } else {
                value.append(character)
            }
        }
        guard quote == nil else { return nil }
        // An unquoted leading `~/` is the home directory, as the shell expands it when it assigns.
        return written.hasPrefix("~/") ? (value as NSString).expandingTildeInPath : value
    }

    /// Whether `text` is a shell variable name.
    static func isName(_ text: Substring) -> Bool {
        guard let first = text.first, first == "_" || (first.isASCII && first.isLetter) else { return false }
        return text.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}

extension ShellVariables {
    /// What the line's walk keeps of one statement: where it sits, whether a use in it may be replaced, and what it binds.
    struct Reading {
        /// The statement's characters, counted from the start of the line.
        let span: Range<Int>
        /// Whether the statement starts at the top of the line and opens no compound command.
        let substitutes: Bool
        /// The name and value the statement binds, if it is a binding statement reached unconditionally at the top.
        let binding: (name: String, value: String)?
    }

    /// A name some word on the line assigns, and the character where that word names it.
    struct Unbinding {
        /// The name assigned.
        let name: String
        /// Where the name is written, counted from the start of the line.
        let offset: Int
    }

    /// A substitution, subshell or group still open where a line is being read.
    struct Frame {
        /// The character that closes it.
        let closer: Character
        /// Whether the text around it was inside double quotes, restored once it closes.
        let inDouble: Bool
    }

    /// Whether the statements read so far leave the next one at the top of the line, outside every group and compound command.
    struct Scope {
        /// The words that open a compound command; a statement starting with one never has a use replaced.
        static let compoundOpeners: Set<String> = ["if", "for", "while", "until", "case", "select", "function", "foreach", "repeat"]

        private var compounds = 0
        private var parentheses = 0
        private var braces = 0
        /// Set once the depth cannot be followed, a `case` pattern's lone `)` for one; nothing binds after it.
        private var lost = false

        var isTopLevel: Bool {
            !lost && compounds == 0 && parentheses == 0 && braces == 0
        }

        /// Takes in the groups and compound commands `statement` opens or closes.
        mutating func enter(_ statement: String) {
            let words = ShellSyntax.tokens(of: statement, stripQuotes: false)
            switch words.first {
            case "if", "for", "while", "until", "case", "select": compounds += 1
            case "fi", "done", "esac": compounds -= 1
            default: break
            }
            braces += words.count(where: { $0 == "{" }) - words.count(where: { $0 == "}" })
            let visible = ShellSyntax.executableText(of: statement)
            parentheses += visible.count(where: { $0 == "(" }) - visible.count(where: { $0 == ")" })
            lost = lost || compounds < 0 || braces < 0 || parentheses < 0
        }
    }

    /// Every word on the line that assigns a name, wherever it sits: a `NAME=` or `NAME+=` word, an element of one, or a loop naming it.
    ///
    /// Read off the raw text, quotes and all, so a word that only looks like an assignment unbinds too: a name is left unread rather than read with a value it may no longer hold.
    static func unbindings(in command: String) -> [Unbinding] {
        let offset = { (index: String.Index) in command.distance(from: command.startIndex, to: index) }
        var found = command.matches(of: /(?:^|[\s;&|(){}`"'])([A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?\+?=/).map {
            Unbinding(name: String($0.output.1), offset: offset($0.output.1.startIndex))
        }
        for loop in command.matches(of: /(?:^|[\s;&|(){}`])(?:for|select|foreach)((?:\s+[A-Za-z_][A-Za-z0-9_]*)+)/) {
            found += loop.output.1.split(whereSeparator: \.isWhitespace).map { Unbinding(name: String($0), offset: offset(loop.output.1.startIndex)) }
        }
        return found
    }

    /// Whether anything on the line can assign a name without a plain assignment word: a builtin that assigns, an arithmetic context, an assigning expansion, `IFS`, or a command the text does not name.
    ///
    /// Such a line binds nothing at all, wherever the thing sits, since what it assigns cannot be read off the text.
    static func rebindsOtherwise(_ command: String) -> Bool {
        if command.contains("((") || command.contains("$[") {
            return true
        }
        if command.contains(/(?:^|[^A-Za-z0-9_])IFS(?:\[[^\]]*\])?\+?=/) || command.contains(/\$\{#?[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?:{0,2}=/)
            || command.contains(/\{[A-Za-z_][A-Za-z0-9_]*\}[<>]/)
        {
            return true
        }
        return commandWords(of: command).contains { words, afterClose in
            guard let name = words.first else { return false }
            // After a closing parenthesis or backtick the words may be a substitution's arguments, so only a builtin's name counts there.
            if !afterClose && (name.contains("$") || name.contains("`")) || assigningBuiltins.contains(name) {
                return true
            }
            let flag = ["printf": "-v", "print": "-v", "wait": "-p"][name]
            return flag.map { flag in words.dropFirst().contains { $0.hasPrefix(flag) } } ?? false
        }
    }

    /// The builtins that can assign a name, each by its own syntax rather than a plain assignment word.
    static let assigningBuiltins: Set<String> = [
        "eval", "source", ".", "read", "declare", "typeset", "local", "export", "readonly", "mapfile", "readarray",
        "getopts", "unset", "let", "integer", "float", "vared", "zparseopts", "zstyle", "trap", "coproc",
    ]

    /// The words of each simple command on the line from its command name on, quotes and backslashes taken out, cut wherever a command can start.
    ///
    /// Cut at every separator, parenthesis and backtick, quoted or not, and at a brace standing as a word of its own; leading assignment words and the words that only introduce a command (`!`, `then`, `command`, `time` and the like) are dropped. Each piece says whether it follows a closing parenthesis or backtick.
    static func commandWords(of command: String) -> [(words: [String], afterClose: Bool)] {
        let introducers: Set = ["!", "if", "then", "elif", "else", "do", "while", "until", "time", "command", "builtin", "exec", "noglob", "nocorrect"]
        var pieces: [(text: String, afterClose: Bool)] = [("", false)]
        var backticks = 0
        for character in command {
            guard ";&|()`\n".contains(character) else {
                pieces[pieces.count - 1].text.append(character)
                continue
            }
            if character == "`" {
                backticks += 1
            }
            pieces.append(("", character == ")" || character == "`" && backticks.isMultiple(of: 2)))
        }
        var commands: [(words: [String], afterClose: Bool)] = []
        for (piece, closed) in pieces {
            var current: [String] = []
            var introduced = false
            var afterClose = closed
            for raw in piece.split(whereSeparator: \.isWhitespace) {
                if raw == "{" || raw == "}" {
                    commands.append((current, afterClose))
                    current = []
                    introduced = false
                    afterClose = false
                    continue
                }
                let word = String(raw.filter { $0 != "\"" && $0 != "'" && $0 != "\\" })
                if current.isEmpty {
                    let assigns = word.firstIndex(of: "=").map { isName(word[..<$0].split(separator: "[").first?.split(separator: "+").first ?? "") } ?? false
                    if assigns || introducers.contains(word) || (introduced && word.hasPrefix("-")) {
                        introduced = introduced || introducers.contains(word)
                        continue
                    }
                }
                current.append(word)
            }
            commands.append((current, afterClose))
        }
        return commands
    }

    /// `command` with each use `value` gives a value for replaced, reading quotes, substitutions and groups as the shell does.
    ///
    /// Only a use outside every substitution, subshell and group is offered to `value`, with the character it starts at.
    static func substituted(_ command: String, value: (_ name: String, _ offset: Int) -> String?) -> String {
        let characters = Array(command)
        var result = ""
        var inDouble = false
        var frames: [Frame] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "\\", let next {
                result.append(character)
                result.append(next)
                index += 2
                continue
            }
            if character == "'", !inDouble {
                let close = characters[(index + 1)...].firstIndex(of: "'") ?? characters.count - 1
                result += String(characters[index ... close])
                index = close + 1
                continue
            }
            if character == "$" {
                if frames.isEmpty, let (name, length) = use(in: characters, at: index), let bound = value(name, index) {
                    result += inDouble ? doubleQuoted(bound) : unquoted(bound)
                    index += length
                    continue
                }
                if let next, next == "(" || next == "{" {
                    frames.append(Frame(closer: next == "(" ? ")" : "}", inDouble: inDouble))
                    inDouble = false
                    result += "$\(next)"
                    index += 2
                    continue
                }
            }
            switch character {
            case "\"":
                inDouble.toggle()
            case "`":
                if frames.last?.closer == "`" {
                    inDouble = frames.removeLast().inDouble
                } else {
                    frames.append(Frame(closer: "`", inDouble: inDouble))
                    inDouble = false
                }
            case "(" where !inDouble:
                frames.append(Frame(closer: ")", inDouble: false))
            case "{" where !inDouble:
                frames.append(Frame(closer: "}", inDouble: false))
            case ")" where !inDouble, "}" where !inDouble:
                if frames.last?.closer == character {
                    inDouble = frames.removeLast().inDouble
                }
            default:
                break
            }
            result.append(character)
            index += 1
        }
        return result
    }

    /// The name a `$NAME` or `${NAME}` at `index` uses and how many characters it spans, or nil for any other form.
    private static func use(in characters: [Character], at index: Int) -> (name: String, length: Int)? {
        let isNameCharacter = { (character: Character) in character == "_" || (character.isASCII && (character.isLetter || character.isNumber)) }
        var end = index + 1
        let braced = end < characters.count && characters[end] == "{"
        if braced {
            end += 1
        }
        let start = end
        while end < characters.count, isNameCharacter(characters[end]) {
            end += 1
        }
        let name = String(characters[start ..< end])
        guard isName(Substring(name)) else { return nil }
        guard braced else { return (name, end - index) }
        return end < characters.count && characters[end] == "}" ? (name, end + 1 - index) : nil
    }

    /// A value spelled inside double quotes: as written, or closing the quotes around a single-quoted run where it holds a character they would read.
    private static func doubleQuoted(_ value: String) -> String {
        value.contains(where: { $0 == "\"" || $0 == "\\" }) ? "\"" + singleQuoted(value) + "\"" : value
    }

    /// A value spelled unquoted: as written, or single-quoted where it holds a character the shell would read again.
    private static func unquoted(_ value: String) -> String {
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_./,:@%+=-".contains($0)) } ? value : singleQuoted(value)
    }

    /// `text` as one single-quoted shell word.
    private static func singleQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
