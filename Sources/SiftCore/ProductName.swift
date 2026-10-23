//
// Copyright © Agulhas Labs
//

/// The product's name, and every name derived from it: the binary, the state directories, the config file, the backup suffix, the MCP server, the tool prefix and the environment variables.
public struct ProductName: Sendable, Hashable, CustomStringConvertible {
    /// The name this build ships under.
    public static let current = ProductName(word: "swift-sure", displayName: "SwiftSure")

    // MARK: Historical names

    /// The npm package earlier releases shipped as; uninstall still recognises it.
    public static var npmPackage: String {
        "@agulhas-labs/sift"
    }

    /// The Claude Code plugin earlier releases enabled for the band, as `claude plugin` names it; uninstall still removes it.
    public static var legacyBandPlugin: String {
        "sift-band@sift"
    }

    /// The local marketplace earlier releases registered for the band, as `claude plugin marketplace` names it; uninstall still removes it.
    public static var legacyBandMarketplace: String {
        "sift"
    }

    /// The key a replayed call's payload carries an answered call's text under.
    ///
    /// It stays as it is across a rename: transcripts already written carry it.
    public static var replayAnswerKey: String {
        "sift_answer_text"
    }

    /// The key a replayed call's payload carries the context's latest prompt under.
    ///
    /// It stays as it is across a rename: transcripts already written carry it.
    public static var replayPromptKey: String {
        "sift_latest_prompt"
    }

    /// The key a replayed call's payload carries the context's size under.
    ///
    /// It stays as it is across a rename: transcripts already written carry it.
    public static var replayContextKey: String {
        "sift_context_tokens"
    }

    /// The word earlier hooks appended to the first statement they wrapped, which `swift-sure run` still takes off.
    ///
    /// It stays as it is across a rename: it names a word those hooks wrote, so a derived spelling would strip a word no hook wrote and pass the written one on to the wrapped command.
    public static var rewriteMarker: String {
        "--sift-rewritten"
    }

    /// The key a `test` run is recorded under in the run usage log.
    ///
    /// It is a persisted key: lines already written carry it, and `report` groups runs by it, so it stays as it is across a rename.
    public static var testRunLogKey: String {
        "sift test"
    }

    /// The names earlier releases shipped under, newest first: what they left on disk and in settings is still read and removed.
    public static let legacy: [ProductName] = [ProductName(word: "sift", displayName: "Sift")]

    /// The extra command names linked to the binary, which are other names for the current product and not earlier ones.
    public static let aliases: [String] = []

    /// Every name this build answers to: the current one, then each legacy one.
    public static var recognised: [ProductName] {
        [current] + legacy
    }

    /// Whether `word` is the executable's name under any name this build answers to.
    public static func isBinary(_ word: String) -> Bool {
        isBinary(word, recognising: recognised)
    }

    /// Whether `word` is the executable's name of a product in `products`.
    public static func isBinary(_ word: String, recognising products: [ProductName]) -> Bool {
        products.contains { $0.binary == word }
    }

    /// How many leading words of `words` spell the executable of a product in `products`: one for its name, alone or at the end of a path, two for the `swift <rest>` form, or `nil` where they spell none.
    public static func binarySpellingLength(of words: [String], recognising products: [ProductName] = recognised) -> Int? {
        guard let first = words.first else { return nil }
        let name = first.split(separator: "/").last.map(String.init) ?? first
        if isBinary(name, recognising: products) {
            return 1
        }
        guard name == "swift", words.count > 1,
              products.contains(where: { $0.driverSpelling?.last == words[1] }) else { return nil }
        return 2
    }

    /// `call` without the executable's name and the space after it, in either spelling, for the first product in `products` whose name begins it, or `nil` where none does.
    public static func removingBinary(from call: String, recognising products: [ProductName] = recognised) -> String? {
        for product in products {
            let spellings = [product.binary] + (product.driverSpelling.map { [$0.joined(separator: " ")] } ?? [])
            for spelling in spellings where call.hasPrefix(spelling + " ") {
                return String(call.dropFirst(spelling.count + 1))
            }
        }
        return nil
    }

    /// The prefix the harness gives every tool of an MCP server a plugin ships: the plugin's name and the server's follow it.
    public static var pluginToolPrefix: String {
        "mcp__plugin_"
    }

    /// The lowercase word the name is spelled with on disk and on a command line.
    public let word: String

    /// The capitalised spelling used for file names and prose.
    public let displayName: String

    public init(word: String, displayName: String) {
        self.word = word
        self.displayName = displayName
    }

    public var description: String {
        word
    }

    /// The executable's name.
    public var binary: String {
        word
    }

    /// The two words a binary named `swift-<rest>` is also run as through SwiftPM's `swift` driver, `swift <rest>`, or `nil` for a binary that has no such spelling.
    public var driverSpelling: [String]? {
        guard binary.hasPrefix("swift-"), binary.count > "swift-".count else { return nil }
        return ["swift", String(binary.dropFirst("swift-".count))]
    }

    /// The directory the tool owns, both in a repository and under the home directory.
    public var directoryName: String {
        "." + word
    }

    /// The per-repository configuration file.
    public var configFileName: String {
        "." + word + ".json"
    }

    /// The suffix of the copy kept beside a settings file the tool rewrites.
    public var backupSuffix: String {
        ".bak-" + word
    }

    /// The name the MCP server registers and answers under.
    public var mcpServer: String {
        word
    }

    /// The prefix of every MCP tool the server offers.
    public var toolPrefix: String {
        "mcp__" + word + "__"
    }

    /// The server's name as the harness spells it inside a plugin's tool name: every character outside letters, digits, `_` and `-` becomes `_`.
    public var pluginServerSegment: String {
        String(mcpServer.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
    }

    /// A hook matcher for the tools of the server when a plugin ships it: the plugin's name, then the server's, then `suffix`.
    public func pluginToolMatcher(_ suffix: String) -> String {
        Self.pluginToolPrefix + ".*_" + pluginServerSegment + "__" + suffix
    }

    /// The directory under a bundle's `share` that holds the files shipped for the tool.
    public var shareDirectory: String {
        word
    }

    /// The file name of the agent rule the tool installs.
    public var ruleFileName: String {
        displayName + ".md"
    }

    /// The prefix every environment variable the tool reads begins with.
    public var environmentPrefix: String {
        binary.uppercased().replacingOccurrences(of: "-", with: "_") + "_"
    }

    /// The infix of the name a set-aside restore keeps what it moved aside under, beside the path.
    public var keptPrefix: String {
        directoryName + "-kept-"
    }

    /// The environment variable the tool reads for `suffix`.
    func environmentVariable(_ suffix: String) -> String {
        environmentPrefix + suffix
    }
}
