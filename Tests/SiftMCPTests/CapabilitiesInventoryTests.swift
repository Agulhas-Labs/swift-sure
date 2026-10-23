//
// Copyright © Agulhas Labs
//

import Foundation
import Testing

/// `Docs/Capabilities.md` inventories every subcommand with the same fields, and keeps in step with the command tree.
///
/// The subcommands and their options come from the parser's own dump, the same one the Guide's command reference is checked against, with the same list of entry points left out by name.
struct CapabilitiesInventoryTests {
    /// The fields every section carries, each as the label its line opens with.
    static let fields = ["Does", "Flags", "Needs a build", "Typical time", "Sample", "Mentioned in"]

    /// Options no section need carry: the parser's own, on every command.
    static let exemptOptions: Set = ["--help", "--version"]

    /// Every subcommand the root command registers, bar the exempt ones, has a section of its own.
    @Test
    func everySubcommandHasASection() throws {
        let commands = try GuideCommandReferenceTests.commandTree()
        let sections = try Self.sections()

        #expect(commands.count > 20)
        for command in commands where GuideCommandReferenceTests.exemptSubcommands[command.name] == nil {
            #expect(sections[command.name] != nil, "`swift-sure \(command.name)` has no `### `swift-sure \(command.name)`` heading in Docs/Capabilities.md")
        }
    }

    /// Every section names a subcommand that exists, so a removed command leaves no stale section behind.
    @Test
    func everySectionNamesARealSubcommand() throws {
        let names = try Set(GuideCommandReferenceTests.commandTree().map(\.name))
        let sections = try Self.sections()

        #expect(sections.count > 20, "only \(sections.count) sections were found")
        for name in sections.keys.sorted() {
            #expect(names.contains(name), "Docs/Capabilities.md has a section for `swift-sure \(name)`, which is not a subcommand")
            #expect(GuideCommandReferenceTests.exemptSubcommands[name] == nil, "Docs/Capabilities.md has a section for `swift-sure \(name)`, an exempt entry point")
        }
    }

    /// Every option `--help` shows for a subcommand is on that section's Flags line.
    @Test
    func everyOptionIsOnItsSectionsFlagsLine() throws {
        let sections = try Self.sections()
        var checked = 0

        for command in try GuideCommandReferenceTests.commandTree() where GuideCommandReferenceTests.exemptSubcommands[command.name] == nil {
            let flags = Self.field("Flags", in: sections[command.name] ?? "") ?? ""
            for option in command.displayedOptions where !Self.exemptOptions.contains(option) {
                checked += 1

                #expect(GuideCommandReferenceTests.mentions(option, in: flags), "`swift-sure \(command.name) \(option)` is not on the Flags line of its section in Docs/Capabilities.md")
            }
        }

        #expect(checked > 50, "only \(checked) options were checked")
    }

    /// Every flag a section's Flags line names is an option of that command, so a flag that does not exist fails.
    @Test
    func everyFlagOnAFlagsLineExists() throws {
        let sections = try Self.sections()
        var checked = 0

        for command in try GuideCommandReferenceTests.commandTree() where GuideCommandReferenceTests.exemptSubcommands[command.name] == nil {
            let flags = Self.field("Flags", in: sections[command.name] ?? "") ?? ""
            let known = Set(command.allOptions).union(Self.exemptOptions)
            for token in Self.flagTokens(in: flags) {
                checked += 1

                #expect(known.contains(token), "the Flags line of `swift-sure \(command.name)` in Docs/Capabilities.md names `\(token)`, which is not an option of that command")
            }
        }

        #expect(checked > 50, "only \(checked) flags were checked")
    }

    /// The `--name` tokens in a line of text.
    static func flagTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: "--") {
            let word = rest[range.lowerBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" }
            let token = String(word)
            if token.count > 2, !token.hasPrefix("---") {
                tokens.append(token)
            }
            rest = rest[range.upperBound...]
        }
        return tokens
    }

    /// Every section has all six field lines, each with something after its label.
    @Test
    func everySectionHasEveryField() throws {
        for (name, body) in try Self.sections().sorted(by: { $0.key < $1.key }) {
            for label in Self.fields {
                let value = Self.field(label, in: body)

                #expect(value != nil, "the section for `swift-sure \(name)` has no `- **\(label):**` line")
                #expect(value?.isEmpty == false || label == "Sample", "the `- **\(label):**` line of `swift-sure \(name)` is empty")
            }
        }
    }

    /// The sections of `Docs/Capabilities.md`, keyed by the subcommand each heading names.
    static func sections(sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: String] {
        let url = GuideCommandReferenceTests.repositoryRoot.appendingPathComponent("Docs/Capabilities.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        var sections: [String: String] = [:]
        var current: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("### `swift-sure ") {
                let name = line.dropFirst("### `swift-sure ".count).prefix { $0 != "`" && $0 != " " }
                current = String(name)
                sections[String(name), default: ""] += ""
            } else if line.hasPrefix("## ") {
                current = nil
            } else if let current {
                sections[current, default: ""] += line + "\n"
            }
        }
        try #require(!sections.isEmpty, "Docs/Capabilities.md has no `### `swift-sure …`` sections", sourceLocation: sourceLocation)
        return sections
    }

    /// What follows `- **label:**` in a section, to the next field line; `nil` where the line is missing.
    ///
    /// A fenced block under the label belongs to it, so the Sample field's value is the block.
    static func field(_ label: String, in body: String) -> String? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("- **\(label):**") }) else { return nil }
        var value = String(lines[start].dropFirst("- **\(label):**".count))
        for line in lines[(start + 1)...] {
            if line.hasPrefix("- **") {
                break
            }
            value += "\n" + line
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
