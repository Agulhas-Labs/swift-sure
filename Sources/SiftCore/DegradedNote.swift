//
// Copyright © Agulhas Labs
//

import Foundation

/// The one note a `where` answer carries under its header when the index store's relations are withheld from it: why, what was withheld, and the remedy a reader acts on (Docs/Design.md §2, *The degraded note*).
///
/// It stands in for the mode line, the absence notice and the `references:` line, which said one thing three times. It names what was withheld, since with no mode line a reader must still learn what the list is not, and says "by written name" only where a written-name list follows it.
struct DegradedNote {
    let cause: Cause
    let withheld: Withheld

    /// How a no-store note opens.
    static var noStoreOpening: String {
        "no store for "
    }
}

extension DegradedNote {
    /// Why the store's relations are withheld.
    enum Cause {
        /// No index store: the remedy clause, each setting passed over, and the clause saying the in-tree walk was cut short.
        case noStore(remedy: String, passedOver: [String], cutShort: String)
        /// A store still loading past this query's budget.
        case warming
        /// A store found that failed to open: which store (its label or in-tree path, when the note names it), and why.
        case openFailed(store: String?, why: String)
        /// The caller turned the store off with `--syntactic`.
        case off
        /// An `--at` answer, read from git at the revision as written.
        case revision(String)
    }

    /// What the answer lists in place of the store's relations.
    enum Withheld {
        /// Callers, overrides and references, matched by written name.
        case calls
        /// A type's uses, matched by written name.
        case uses
        /// Both: some declarations are types and some are not.
        case mixed
        /// Nothing: every declaration left is a subscript, whose uses spell no name to match.
        case subscripts
    }

    /// How a subscript's note opens, whatever the cause.
    static var subscriptOpening: String {
        "subscript: callers and references withheld, uses spell no name to match"
    }

    /// The remedy a checkout with no store is pointed at.
    static var checkoutRemedy: String {
        "how to build one: \(ProductName.current.binary) help answers, section (index store)"
    }

    /// What opens the clause that carries a checkout remedy's root flag.
    private static var checkoutRootOpening: String {
        "; run that build with "
    }

    /// The remedy a checkout with no store is pointed at, naming the root (`rootFlag`, ``StoreRemedy/rootFlag(root:currentDirectory:)``) where the help topic's plain build command would build another checkout.
    static func checkoutRemedy(rootFlag: String) -> String {
        rootFlag.isEmpty ? checkoutRemedy : "\(checkoutRemedy)\(checkoutRootOpening)\(rootFlag.trimmingCharacters(in: .whitespaces))"
    }

    /// The remedy for files outside every open store's package: only a build of their own project gives them a store.
    static var outsideRemedy: String {
        "build the files' own project for its store"
    }

    /// What opens the remedy a worktree with a `Package.swift` at its root is told, before its root flag.
    private static var packageRemedyOpening: String {
        "build: \(ProductName.current.binary) run "
    }

    /// What follows that remedy's root flag.
    private static var packageRemedyClosing: String {
        "-- swift build --build-tests (\(ProductName.current.binary) help worktree-index)"
    }

    /// The remedy a worktree with a `Package.swift` at its root is told: its one build command, carrying `rootFlag` (``StoreRemedy/rootFlag(root:currentDirectory:)``) where the answer's root is not the directory SwiftSure runs in.
    static func packageRemedy(rootFlag: String) -> String {
        "\(packageRemedyOpening)\(rootFlag)\(packageRemedyClosing)"
    }

    /// The remedy any other worktree is pointed at.
    static var worktreeRemedy: String {
        "how to build one: \(ProductName.current.binary) help worktree-index"
    }

    /// `index store failed to open (<store>: <why>)`, the store named so a reader knows which one to fix.
    private static func openFailedOpening(store: String?, why: String) -> String {
        "index store failed to open (\(store.map { "\($0): " } ?? "")\(why))"
    }

    /// The clause a uses-withholding note carries; an answer that ends in the standing caveats (``StandingCaveats``) drops it, so it says one.
    static var emptyListClause: String {
        ", an empty list is not \"unused\""
    }

    var line: String {
        let sites = "sites by written name" + (withheld == .uses || withheld == .mixed ? Self.emptyListClause : "")
        let what = switch withheld {
        case .calls, .subscripts: "callers, overrides or references"
        case .uses: "uses"
        case .mixed: "callers, overrides, uses or references"
        }
        if withheld == .subscripts {
            return "\(Self.subscriptOpening); \(subscriptCause)"
        }
        return switch cause {
        case .noStore: "\(Self.noStoreOpening)\(what); \(sites)\(noStoreTail)"
        case .warming: "index store still loading: \(what) withheld, \(sites); ask again shortly"
        case let .openFailed(store, why): "\(Self.openFailedOpening(store: store, why: why)): \(what) withheld, \(sites)"
        case .off: "--syntactic: \(what) not asked for, \(sites)"
        case let .revision(revision): "--at \(revision): \(what) not available from git, \(sites)"
        }
    }

    /// The one line a no-match answer carries where there is no store: nothing is listed to qualify, so only the way to build one is said; `nil` for any other cause.
    var pointer: String? {
        guard case .noStore = cause else { return nil }
        return "no store\(noStoreTail)"
    }

    /// A subscript's note names the cause after what it withheld, with the no-store or warming remedy.
    private var subscriptCause: String {
        switch cause {
        case .noStore: "no store\(noStoreTail)"
        case .warming: "index store still loading, ask again shortly"
        case let .openFailed(store, why): Self.openFailedOpening(store: store, why: why)
        case .off: "not asked for (--syntactic)"
        case let .revision(revision): "not available from git (--at \(revision))"
        }
    }

    /// The remedy, each setting passed over and a cut-short walk, each after `; `.
    private var noStoreTail: String {
        guard case let .noStore(remedy, passedOver, cutShort) = cause else { return "" }
        return "; \(remedy)" + (passedOver.isEmpty ? "" : "; passed over: " + passedOver.joined(separator: "; ")) + cutShort
    }

    /// `line` with its build remedy taken out, where a project-build hint names the build in its place; any other line comes back unchanged.
    static func withoutRemedy(_ line: String) -> String {
        guard line.hasPrefix(noStoreOpening) || line.hasPrefix(subscriptOpening) else { return line }
        var result = line.replacingOccurrences(of: "; \(worktreeRemedy)", with: "")
        if let remedy = result.range(of: "; \(checkoutRemedy)") {
            var end = remedy.upperBound
            if result[end...].hasPrefix("\(checkoutRootOpening)--root ") {
                end = StoreRemedy.endOfShellWord(in: result, from: result.index(end, offsetBy: checkoutRootOpening.count + "--root ".count))
            }
            result.removeSubrange(remedy.lowerBound ..< end)
        }
        if let opening = result.range(of: "; \(packageRemedyOpening)"),
           let closing = result.range(of: packageRemedyClosing, range: opening.upperBound ..< result.endIndex)
        {
            result.removeSubrange(opening.lowerBound ..< closing.upperBound)
        }
        return result
    }
}
