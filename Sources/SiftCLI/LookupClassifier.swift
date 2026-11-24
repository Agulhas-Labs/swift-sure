//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore
import SiftMCP

/// Decides what a call's lookup is, and whether the index could have answered it with a call that can be made.
struct LookupClassifier {
    private init() {}

    typealias Lookup = PreToolUseCommand.Lookup

    /// `lookup`, where the index could have served it with a call that can be made, or `nil` where a rule withholds it, logged under that rule and against `call`, the judged call's `tool_use_id`.
    static func worthAsking(
        _ lookup: Lookup,
        in directory: String?,
        noting suppressions: SuppressionLog,
        call: String?,
        couldAnswer: (String, String?) -> Bool = { AdvisableName.couldAnswer($0, from: $1) }
    ) -> Lookup? {
        // The advisor built a suggestion because the miss is real and the metric must go on counting it;
        // what this adds is that the index could not have served *this* question — a count, a sweep whose
        // pattern names nothing, prose on one file, a literal, a merge's markers, a tree no index holds
        // (`TextSearch`). Withheld here rather than in the advisor so that both ends still answer together,
        // and logged under the rule that decided, like every other withholding.
        if let reason = lookup.textSearch {
            suppressions.note(symbol: lookup.suggestion.symbol, directory: directory, rule: reason.rawValue, call: call)
            return nil
        }
        // A refusal has to offer a call that can be made, and a bare `search` asks the caller to write the query
        // the advisor could not. It is built only where no index call answers the lookup — a phrase of ordinary
        // words, or an alternation with one in it (`SweepPattern`) — so the scan scores it out of the share on the
        // same property, and the two ends still agree.
        if !lookup.suggestion.namesATarget {
            suppressions.note(symbol: nil, directory: directory, rule: "untargeted", call: call)
            return nil
        }
        // Several names are one `where` per name of an alternation — as many questions as the caller asked — and
        // a `where` for a name no index declares answers "no symbol named". So the ask is answered whole or not
        // at all: where any of the names is undeclared the hook says nothing and the search runs
        // (`partlyDeclared`). Offering the declared subset instead would answer a question nobody asked, and
        // silently — the caller wanted every branch, and the narrowing appears nowhere in the refusal. Staying
        // quiet costs nothing, because the search the advice would have interrupted simply goes through; wrong
        // advice is the expensive failure here, not a missed nudge. One file's digest standing on several names
        // (`IndexSuggestion.forSearch`) is not that shape and would not be narrowed here: it answers for the file
        // whatever the names are, so one declared name among them would be enough. Nothing reaches this gate in
        // that shape, though — an alternation confined to the files it names is withheld a rule earlier, on the
        // price of the offer rather than on the names (`TextSearch.Reason.severalNames`). The scan asks the same
        // of both.
        let symbols = lookup.suggestion.symbols
        if !symbols.isEmpty {
            let declared = symbols.filter { couldAnswer($0, directory) }
            guard !declared.isEmpty else {
                suppressions.note(symbol: symbols.joined(separator: " "), directory: directory, rule: "unknownName", call: call)
                return nil
            }
            if lookup.suggestion.isOneCallPerName, declared.count < symbols.count {
                suppressions.note(symbol: symbols.joined(separator: " "), directory: directory, rule: "partlyDeclared", call: call)
                return nil
            }
        }
        // No repository, no root: the one tree rule (``SiftMCP/RepositoryIndex/isRootless(for:relativeTo:)``),
        // and the general form of the invariant every advisor states — a refusal has to offer a call that can
        // be made. An unindexed checkout can answer the offered call, because the call indexes it on the way —
        // measured in tenths of a second, and bounded by the hook's own time budget rather than by a gate
        // here. A path standing outside every repository never can, because a call naming a *path* is answered
        // by reading that exact path under a root, and a path with no repository above it resolves none. The
        // answer is `… is in no repository to root at — read it directly`, so the refusal would deny the read
        // and then charge a whole context re-send to ask for it.
        //
        // Asked of the call's own targets rather than of the lookup's anchor, which is what keeps it a claim
        // about the offer: `digest View` names a symbol and is answered out of whatever index the caller's own
        // root resolves to, wherever the file read happened to sit, while `digest /notes/Plan.md` can be
        // answered nowhere. A document is the everyday case, since a `.md` target is always its own path —
        // vault notes, rule files, a plan in a home directory — and the Swift analogue is the same rule.
        //
        // The rule takes nothing out of the share: the lookup still went around an index that could have held
        // it, and the scan goes on counting it. What it decides is only whether the hook spends a turn.
        //
        // Asked only of a path that is *there*. The claim is about the tree a file sits in, and a path naming no
        // file names no tree to make it about — the read is about to fail on its own, and withholding on a
        // judgement the disk cannot support is the one direction this rule must not err in. It is the same
        // preference every gate here has on doubt: say nothing about what cannot be judged, refuse as before.
        if lookup.suggestion.pathTargets.contains(where: { PreToolUseCommand.cannotBeRooted($0, in: directory) }) {
            suppressions.note(symbol: nil, directory: directory, rule: "noRepository", call: call)
            return nil
        }
        // A whole read of a small document is let through: the outline would save a fraction of a read that
        // small, and a wrong guess — the caller wanted the exact text — costs the outline, the file and a round
        // trip over the whole context (``SiftMCP/ReadAdvice/isSmallDocument(_:)``). Asked last, so it is logged
        // only where no other rule had already withheld the read.
        if let path = lookup.readPath, ReadAdvice.isSmallDocument(path) {
            suppressions.note(symbol: nil, directory: directory, rule: "smallDocument", call: call)
            return nil
        }
        return lookup
    }

    /// Notes a call let through because what located each file it reads through a window excuses the window: `digestHeldWindow` where the windows print more than ``SiftMCP/ListedWindow/widestExcused`` lines of a file, which only its whole digest excuses, `locatedWindow` otherwise, and nothing where `reads` is empty.
    ///
    /// The pass is the loop working and no lookup, so no share counts it, which is why it is written down: the log is the only record of how often a located window, or a wide one after the whole digest, is read rather than answered.
    static func notePass(ofWindows reads: [(path: String, windows: [LineWindow])], in directory: String?, noting suppressions: SuppressionLog, call: String?) {
        guard !reads.isEmpty else { return }
        let rule = reads.contains { ListedWindow.isWide($0.windows, ofFileAt: $0.path) } ? "digestHeldWindow" : "locatedWindow"
        suppressions.note(symbol: nil, directory: directory, rule: rule, call: call)
    }

    /// The lookup beside the reads `reading` let through — a grep whose output is filtered — classified with those reads and the re-runs `allowed` names allowed, or `nil` where the reads were all the line asked.
    ///
    /// Only ever logged under the rule that withholds it, never answered: an answer would deny the reads as well.
    static func lookup(besideReadsOf reading: Lookup, command: String?, payload: [String: Any], in directory: String?, allowed: ([String]) -> Set<String>) -> Lookup? {
        let keys = Set(reading.inPlace?.statements.joined().compactMap { reading.statementKeys[$0] } ?? []).union(reading.usageLogHeldKeys)
        guard !keys.isEmpty, let beside = classified(command: command, payload: payload, in: directory, allowed: { allowed($0).union(keys) }), !keys.contains(beside.key) else { return nil }
        return beside
    }

    /// The line `command` or `payload` carries classified again with `keys` — the statements of reads this context already holds — allowed as re-runs beside the ledger's own, or `nil` where those reads were all it asked.
    static func lookup(besideReads keys: Set<String>, command: String?, payload: [String: Any], in directory: String?, context: AdviceContext, ledger: AdviceLedger) -> Lookup? {
        guard !keys.isEmpty,
              let beside = classified(command: command, payload: payload, in: directory, allowed: { ledger.rerunsAllowed(session: context.key, among: $0).union(keys) }),
              !keys.contains(beside.key)
        else { return nil }
        return beside
    }

    /// The toolchain run a shell line `written` is, as the run advice reads it, or `nil` where it is none.
    static func runLookup(_ written: String) -> Lookup? {
        guard let suggestion = RunAdvice.suggestion(for: written) else { return nil }
        var run = Lookup(key: AdviceLedger.key(forShell: written), suggestion: suggestion, textSearch: nil, rule: "RunAdvice")
        run.alsoReaching = RunAdvice.reachedPaths(of: written)
        return run
    }

    static func classified(
        command: String?,
        payload: [String: Any],
        in directory: String? = nil,
        allowed: ([String]) -> Set<String>
    ) -> Lookup? {
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let tool = command == nil ? LookupTool.rule(for: payload["tool_name"] as? String ?? "") ?? "" : "Bash"

        switch tool {
        case "Bash":
            guard let written = command ?? input["command"] as? String, !written.isEmpty else {
                return nil
            }
            // A lookup is read as though a `tee` ending its pipeline were absent, since what reaches the context
            // is the same; a toolchain run below is read as written, where a `tee` is the caller keeping a log.
            let shellCommand = ShellInspection.withoutPassThroughTees(written)
            // Built once and handed to both readings, so the tree is walked once per call rather than
            // once per question asked about it.
            let holdsSource = SwiftTree.probe(relativeTo: directory)
            // Run mode reads the line for a build or test alone.
            if PreToolUseCommand.isRunOnly {
                return runLookup(written)
            }
            // A lookup first, and a toolchain run only if it was not one. They cannot both match — a
            // `swift build` is a write to `ShellInspection` long before it could be a lookup — and asking
            // in this order keeps that an invariant rather than a coincidence of two advisors' rules.
            // A line of several lookups is about the first one the ledger has not already allowed: every fact
            // below is drawn from that one, so a new lookup behind the re-run of an allowed one is advised on
            // as itself; the allowed one still prints, so the line runs rather than being answered. The ledger is asked only where there is a choice to
            // make, so a line of one lookup reads nothing more than it ever did.
            let keys = ShellAdvice.lookupKeys(for: shellCommand, holdsSource: holdsSource)
            let sanctioned = keys.count > 1 ? allowed(keys) : []
            if let suggestion = ShellAdvice.suggestion(
                for: shellCommand,
                holdsSource: holdsSource,
                directory: directory,
                skipping: sanctioned
            ) {
                // The re-run this refusal promises is recognised by the reading stage alone — pattern, flags
                // and paths — never by the whole line, so a retry that only changes what rides beside the
                // grep is still the same ask. Falls back to the whole command only where the key could not
                // be drawn from a stage, which `suggestion` having matched makes unreachable in practice.
                let key = ShellAdvice.lookupKey(for: shellCommand, holdsSource: holdsSource, skipping: sanctioned)
                    ?? AdviceLedger.key(forShell: shellCommand)
                // The answer runs nothing, so it says what the `tee`s taken out above would have written was not.
                let teed = ShellInspection.passThroughTeeFiles(written)
                let inPlace = ServedReading.match(forShell: shellCommand, in: directory, holdsSource: holdsSource, skipping: sanctioned)
                    .map { teed.isEmpty ? $0 : $0.teeing(teed) }
                return Lookup(
                    key: key,
                    suggestion: suggestion,
                    textSearch: ShellAdvice.textSearchReason(shellCommand, holdsSource: holdsSource, cwd: directory, skipping: sanctioned),
                    searchPath: ShellAdvice.namedPath(for: shellCommand, holdsSource: holdsSource, skipping: sanctioned),
                    inPlace: inPlace,
                    rule: "ShellAdvice",
                    isWindow: ShellAdvice.readsThroughAWindow(shellCommand, holdsSource: holdsSource, skipping: sanctioned),
                    windowPaths: ShellAdvice.windowedReadPaths(shellCommand, holdsSource: holdsSource, cwd: directory),
                    statementKeys: ServedReading.statementKeys(of: inPlace) { ShellAdvice.lookupKey(for: $0, holdsSource: holdsSource) }
                )
            }
            return runLookup(written)
        case "Grep", "Glob":
            guard let suggestion = SearchToolAdvice.suggestion(tool: tool, input: input, in: directory) else {
                return nil
            }
            // Keyed on the arguments that decide the answer, so the retry is recognised however the tool
            // orders or defaults the rest.
            let pattern = input["pattern"] as? String ?? ""
            let path = input["path"] as? String ?? directory ?? ""
            return Lookup(
                key: "\(tool) \(pattern) \(path)",
                suggestion: suggestion,
                textSearch: SearchToolAdvice.textSearchReason(tool: tool, input: input, in: directory),
                searchPath: (input["path"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                inPlace: InPlaceShape.match(forSearchTool: tool, input: input, in: directory),
                rule: "SearchToolAdvice"
            )
        case "Read":
            guard let path = LookupTool.readPath(in: input) else { return nil }
            // The same reading of "ranged" the transcript scan uses: `limit` alone bounds a read too, and
            // an explicit JSON null is not a range.
            let ranged = input["offset"] is NSNumber || input["limit"] is NSNumber
            // A ranged read of a Swift file is judged as the whole read is, and let through as no lookup once
            // this context has located the file; a document's ranged read stays the advisor's to wave through.
            let window = ranged && path.hasSuffix(".swift")
            guard let suggestion = ReadAdvice.suggestion(path: path, ranged: ranged && !window) else { return nil }
            // A read names a file outright, so of `TextSearch`'s rules only the one about where it points can
            // reach it: a file in a tree no index holds, which the scan scores out of the share on the same verdict.
            return Lookup(
                key: "Read \(path)",
                suggestion: suggestion,
                textSearch: TextSearch.reason(forWholeRead: path, cwd: directory),
                readPath: path,
                inPlace: InPlaceShape.match(forRead: path, in: directory, window: window ? LineWindow(offset: (input["offset"] as? NSNumber)?.intValue, limit: (input["limit"] as? NSNumber)?.intValue) : nil),
                rule: "ReadAdvice",
                isWindow: window
            )
        default:
            return nil
        }
    }
}
