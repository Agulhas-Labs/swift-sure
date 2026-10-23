//
// Copyright © Agulhas Labs
//

import Foundation

// MARK: What a query says about the index store it is not using

extension SiftEngine {
    /// The root flag the build commands this engine prints carry (``StoreRemedy/rootFlag(root:currentDirectory:)``), from the directory its caller runs in (``callerDirectory``).
    var storeRootFlag: String {
        StoreRemedy.rootFlag(root: repoRoot, currentDirectory: callerDirectory)
    }

    /// What a query says when there is no store to open — which in a linked worktree means something other than what it means in a checkout.
    ///
    /// Naming the build command is true in both and sufficient in only one. A worktree has no build directory of its own, so a repository whose checkout answers semantically every day answers nothing here, and the caller is in a state they did not create and probably have not noticed. **The obvious repair is the one thing this must never do.** The checkout's store describes a *different tree*: at a different commit it would name callers that do not exist here and miss ones that do, which is the confidently wrong answer that pinning the root to the caller's tree exists to kill — an honest gap turned into a lie, in exchange for looking more complete.
    ///
    /// The worktree case is the one every builder agent hits, on every `where` and every `digest`, so the note it gets stays one line: which state this is, and where the rest of the reasoning lives (``HelpTopics``' `worktree-index` topic — the checkout not being borrowed, and why, is said there in full, not dropped). A plain checkout still gets the build command and the config key inline, on `affected`; `where` carries the degraded note ``whereNoStoreCause(from:)`` reads from it in its place.
    ///
    /// No path is named, per the Answer Contract's Wording rule. The header already names the tree.
    ///
    /// `rejected` carries each `indexStorePath` discovery read and passed over (``IndexStoreDiscovery/rejectedSettings()``): without it, a reader who set the key is told only to set it, which reads as "your setting was never seen" when it was seen and refused.
    ///
    /// Where a `Package.swift` sits at `root`, a worktree's note names the one command that builds its store rather than only the topic, since a pointer alone sent readers to `grep` instead.
    ///
    /// Where `root` is not `currentDirectory`, the build commands carry `--root <root>`, since run from the caller's directory they would build that checkout instead (``StoreRemedy/rootFlag(root:currentDirectory:)``).
    static func noStoreNote(
        for tree: WorkingTree,
        rejected: [String] = [],
        root: URL? = nil,
        currentDirectory: String? = FileManager.default.currentDirectoryPath
    ) -> String {
        let rejection = rejected.isEmpty ? "" : rejected.joined(separator: "; ") + "; "
        let rootFlag = StoreRemedy.rootFlag(root: root, currentDirectory: currentDirectory)
        guard tree.worktree != nil else {
            return "\(noStoreLead)\(rejection)\(checkoutRecipeOpening)\(StoreRemedy.buildText(root: root, rootFlag: rootFlag)). "
                + "\(otherStorePointer). \(syntaxOnlyTail)"
        }
        let packageAtRoot = root.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Package.swift").path) } ?? false
        let howToBuild = packageAtRoot
            ? "\(StoreRemedy.packageBuild(rootFlag: rootFlag)) (`\(ProductName.current.binary) help worktree-index` has why the checkout's is not used)"
            : "run `\(ProductName.current.binary) help worktree-index` for how to build one"
        return "\(noStoreLead)\(rejection)\(worktreeOpening)\(howToBuild). \(syntaxOnlyTail)"
    }

    /// The header's reading of a ``noStoreNote(for:rejected:root:)``: no store in this worktree, or none for this tree yet.
    ///
    /// Read back from the note by the same marker ``whereNoStoreCause(from:)`` reads, so the header and the note cannot name different trees.
    static func noStoreAxis(from note: String) -> SemanticAxis {
        if note.hasPrefix(outsideLead), let end = note.range(of: outsideRemedyOpening) {
            return .noStoreCovering(String(note[note.index(note.startIndex, offsetBy: outsideLead.count) ..< end.lowerBound]))
        }
        return .noStore(inWorktree: note.hasPrefix(noStoreLead) && note.dropFirst(noStoreLead.count).contains(worktreeOpening))
    }

    /// The cause `where`'s degraded note gives for a ``noStoreNote(for:rejected:root:)``: the build remedy, each setting passed over, and a cut-short in-tree walk.
    ///
    /// Read back from the note by the markers it is written with, as ``noStoreAxis(from:)`` reads it, so the header and the note cannot name different trees. A note it does not recognise is kept whole as the remedy.
    static func whereNoStoreCause(from note: String) -> DegradedNote.Cause {
        if note.hasPrefix(outsideLead) {
            let tail = note.range(of: ". " + syntaxOnlyTail)?.lowerBound ?? note.endIndex
            let passedOver = note.range(of: "; passed over: ").map { String(note[$0.upperBound ..< tail]) }
            return .noStore(remedy: DegradedNote.outsideRemedy, passedOver: passedOver.map { [$0] } ?? [], cutShort: "")
        }
        guard note.hasPrefix(noStoreLead) else { return .noStore(remedy: note, passedOver: [], cutShort: "") }
        let body = note.dropFirst(noStoreLead.count)
        let worktree = body.range(of: worktreeOpening)
        let rejection = (worktree ?? body.range(of: checkoutRecipeOpening)).map { String(body[..<$0.lowerBound].dropLast(2)) } ?? ""
        let remedy = if worktree == nil {
            DegradedNote.checkoutRemedy(rootFlag: StoreRemedy.rootFlag(in: note, after: checkoutRecipeOpening + "\(ProductName.current.binary) run ") ?? "")
        } else if let rootFlag = StoreRemedy.packageRootFlag(in: note) {
            DegradedNote.packageRemedy(rootFlag: rootFlag)
        } else {
            DegradedNote.worktreeRemedy
        }
        let cutShort = note.hasSuffix(inTreeWalkTruncatedClause) ? inTreeWalkTruncatedClause : ""
        return .noStore(remedy: remedy, passedOver: rejection.isEmpty ? [] : [rejection], cutShort: cutShort)
    }

    /// Why a store failed to open, as the note an `.openFailed` input carries says it: the text after `failed to open: `, or the whole note.
    static func openFailureCause(of note: String) -> String {
        note.range(of: "failed to open: ").map { String(note[$0.upperBound...]) } ?? note
    }

    /// Which store failed to open, as the note an `.openFailed` input carries names it: the primary store's label (`index store found (<label>) but …`) or the in-tree store's path (`in-tree store <path> failed …`); `nil` when the note names none.
    static func openFailureStore(of note: String) -> String? {
        for (prefix, terminator) in [("index store found (", ")"), ("in-tree store ", " failed to open")] where note.hasPrefix(prefix) {
            let rest = note.dropFirst(prefix.count)
            return rest.range(of: terminator).map { String(rest[..<$0.lowerBound]) }
        }
        return nil
    }

    /// How the degraded note of a `where` or `affected` answer opens when no store answered: the mode, and where to read what it means.
    ///
    /// What matching by written name gives up is the same on every such answer, so it is said once in the `answers` help topic and not on each one. What follows this opening is the part that differs between answers: no store, still warming, or failed to open.
    static var degradedModeOpening: String {
        "mode: syntactic (\(ProductName.current.binary) help answers); "
    }

    /// How a ``noStoreNote(for:rejected:root:)`` opens, before any rejected setting.
    private static var noStoreLead: String {
        "no index store for this tree yet — "
    }

    /// How the note opens for a query about files outside every open store's package, before the store's own scope.
    static var outsideLead: String {
        "no index store covers these files; "
    }

    /// What follows the store's scope in that note, before its remedy.
    static var outsideRemedyOpening: String {
        " — "
    }

    /// What opens a checkout's recipe in a ``noStoreNote(for:rejected:root:)``, after any rejected setting.
    private static var checkoutRecipeOpening: String {
        "build one: "
    }

    /// What opens a worktree's remedy in a ``noStoreNote(for:rejected:root:)``, after any rejected setting.
    private static var worktreeOpening: String {
        "a worktree has none; "
    }

    /// `status`'s one line about the store: where it was found, or how to get one — and, either way, each `indexStorePath` discovery read and rejected.
    ///
    /// A rejection is named whether or not another probe found a store: either way the setting did not act, and "none found", or another provenance, alone reads as the key never having been read.
    ///
    /// Where `root` is not `currentDirectory`, the build commands carry `--root <root>`, as in ``noStoreNote(for:rejected:root:currentDirectory:)``.
    static func storeStatusLine(
        discovered: DiscoveredStore?,
        rejected: [String],
        root: URL? = nil,
        currentDirectory: String? = FileManager.default.currentDirectoryPath
    ) -> String {
        guard let discovered else {
            let rejection = rejected.isEmpty ? "" : rejected.joined(separator: "; ") + "; "
            let rootFlag = StoreRemedy.rootFlag(root: root, currentDirectory: currentDirectory)
            return "index store: none found — \(rejection)build one: \(StoreRemedy.buildText(root: root, rootFlag: rootFlag)). \(otherStorePointer)."
        }
        let passedOver = rejected.isEmpty ? "" : "; passed over: " + rejected.joined(separator: "; ")
        return "index store: \(discovered.label) — \(discovered.path.path)\(passedOver)"
    }

    /// The deleted paths the ledger names that are still missing and that the store may still cite: dropped after the build `anchor`, or named by a unit still on disk, since a build keeps a deleted file's unit until a clean build; sorted, as the ledger's own list is.
    ///
    /// `namedByAUnit` says whether a unit names any of them, every missing path asked, those dated after the build too. `kept` says there is at least one and each was dropped at or before the build and is named by a unit: what only a clean build clears.
    static func deletedFilesTheStoreMayCite(ledger: DeletionLedger, anchor: Double, in discovered: DiscoveredStore, root: URL) -> DeletedFilesCited {
        let droppedAfterBuild = Set(ledger.paths(droppedAfter: anchor))
        let mentions = StoreUnitMentions(store: discovered.path, root: root)
        var paths: [String] = []
        var namedByAUnit = false
        for path in ledger.entries.keys.sorted() where !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            let named = mentions.names(file: path)
            namedByAUnit = namedByAUnit || named
            if named || droppedAfterBuild.contains(path) {
                paths.append(path)
            }
        }
        return DeletedFilesCited(paths: paths, namedByAUnit: namedByAUnit, kept: !paths.isEmpty && paths.allSatisfy { !droppedAfterBuild.contains($0) })
    }

    /// What ``deletedFilesTheStoreMayCite(ledger:anchor:in:root:)`` found: the paths, whether a unit names any, and whether a clean build alone clears them.
    struct DeletedFilesCited {
        let paths: [String]
        let namedByAUnit: Bool
        let kept: Bool
    }

    /// The lines `status` prints after its store line about its semantic field: beside the store it was judged against rather than under the header, where a list printed on every run buried that line.
    ///
    /// The line about a deleted file's record prints only when `unitKeepsADeletedFile`, a unit on disk read and found naming one.
    static func statusAxisLines(discovered: DiscoveredStore?, unitKeepsADeletedFile: Bool) -> [String] {
        guard discovered != nil else { return [] }
        return unitKeepsADeletedFile ? [statusAxisNote, statusDeletedNote] : [statusAxisNote]
    }

    /// What `status` says beside its store line whenever it found one: how its semantic field was judged, and where the cases it cannot see are listed.
    ///
    /// One line, since it prints on every run: the list itself is the help topic's (``HelpTopics``, `answers`), which names each gap Docs/Design.md §2 leaves this reading, and the two must change together.
    static var statusAxisNote: String {
        "The semantic field is judged from files, without opening the index store; `\(ProductName.current.binary) help answers` lists what only a query shows."
    }

    /// What `status` adds when it counts a deleted file: a build does not clear one, since the store keeps a deleted file's unit, and a query citing it goes on marking it, until a clean build.
    static var statusDeletedNote: String {
        "A deleted file stays in the store's record, and in each query citing it, until a clean build; a build without cleaning keeps it."
    }

    /// The one true way to get an index store, said identically everywhere that offers it (Docs/Design.md §2).
    ///
    /// `where`'s no-store note, `status`'s own line, `Design.md` and `INSTALL.md` all quote this same command pair rather than each inventing its own. Carries no trailing period: every call site supplies its own. Kept apart from ``nestedStoreNote`` so a sentence offering an alternative to building can sit after the commands without reading as an alternative to the config key.
    ///
    /// SwiftPM's command carries `--build-tests`: a plain `swift build` compiles no test target, so its store records no reference from a test and every answer about tests reads `partial`.
    ///
    /// Not `private`: ``HelpTopics``' `worktree-index` topic quotes it too, so the command it tells a reader to run cannot drift from what a per-call note says.
    ///
    /// `-destination 'generic/platform=iOS Simulator'` alone builds both `arm64` and `x86_64` — the simulator SDK's `ARCHS_STANDARD` carries the Intel slice even though `swift-sure` itself never ships one — so the note narrows to the host architecture and pays for one architecture instead of two.
    static var buildCommandNote: String {
        StoreRemedy.buildCommand(rootFlag: "")
    }

    /// Where discovery looks, and for a store anywhere else, the config line that points at it.
    ///
    /// The places are named so a reader who built into a directory of their own choosing can tell whether it is one of them, and each is one ``IndexStoreDiscovery/discover()`` probes: an ignored directory in general is not, since the in-tree walk serves only `where`, beside a primary. The key resolves against the repository root, so the example carries the build directory's own path. A SwiftPM build of a nested package is searched, so only a custom `-derivedDataPath` needs the key. No trailing period, as ``buildCommandNote``.
    ///
    /// Not `private`, for the same reason as ``buildCommandNote``: ``HelpTopics``' `worktree-index` topic quotes it rather than keeping a second copy that could drift.
    static let nestedStoreNote = "Discovery searches the repo root's .build, the .build of each package nested below "
        + "it (a directory holding a Package.swift), Xcode's own DerivedData, \(ProductName.current.directoryName)/DerivedData (a linked worktree's `\(ProductName.current.binary) run -- xcodebuild` builds there), and "
        + "-derivedDataPath <Pkg>/.build/DerivedData where <Pkg> is the repo root or a directory holding a Package.swift; "
        + "any other custom -derivedDataPath needs indexStorePath set in \(ProductName.current.configFileName), "
        + "pointing at the store directory itself — the one holding v<N>/units, relative to the repo root: "
        + "<path>/Index.noindex/DataStore for a custom -derivedDataPath <path>, "
        + "as in {\"indexStorePath\": \"<path>/Index.noindex/DataStore\"}"

    /// The one clause a no-store line ends with in place of the whole discovery list: a store built anywhere else needs the config key, and the Guide lists where discovery looks.
    static var otherStorePointer: String {
        "A store built elsewhere needs indexStorePath set in \(ProductName.current.configFileName); Docs/Guide.md §7 lists where discovery looks"
    }

    /// How ``inMemoryIndexNote`` opens, public so the transcript reader that skips the line (`SourcePassthrough.firstPartLine(of:)`) matches the renderer's own text rather than a retyped copy.
    public static var inMemoryIndexNoteOpening: String {
        "index: in memory"
    }

    /// What ``memoryIndexNote`` says of an index held in memory because the question asked for nothing to be stored.
    static var syntacticIndexNote: String {
        "\(inMemoryIndexNoteOpening) — --syntactic answers from the source as it stands and stores nothing under this tree"
    }

    /// What ``memoryIndexNote`` says.
    static var inMemoryIndexNote: String {
        "\(inMemoryIndexNoteOpening) — this tree cannot be written, so nothing is stored under it and the index lasts only as long as this process"
    }

    /// Internal rather than `private`: `AffectedRenderer`'s own no-store preamble strips this exact clause off the shared note (it answers with tests, not declarations/callers/overrides), and a second copy of the string would let the wording drift out of what the strip matches.
    static let syntaxOnlyTail = "Until then, declarations still answer from syntax; callers, "
        + "overrides and references do not."

    /// What the degraded `where` note adds when the in-tree walk (``InTreeStoreWalk``) hit its cap with directories still unvisited (Docs/Design.md §2) — a store beyond where it stopped may exist.
    ///
    /// Not `private`: `WhereRenderer` matches this exact suffix to suppress the project hint in that case, since "build it with -derivedDataPath inside the tree" is exactly the advice a reader who already did that does not need repeated.
    static let inTreeWalkTruncatedClause = "; in-tree walk cut short at \(InTreeStoreWalk.visitCap) directories"

    /// What a query says while the store is still ingesting.
    ///
    /// It has to separate itself from the refusal standing beside it, because the two read alike and mean opposite things. "Build the project" means the data does not exist yet and re-asking is pointless; this means the data exists and is being read, and re-asking is the entire remedy. Saying so plainly is what stops a caller treating a slow store as a broken one and going back to grep.
    static func warmingNote(provenance: DiscoveredStore.Provenance, seconds: TimeInterval) -> String {
        "index store found (\(provenance.name)) but still warming — \(Int(seconds.rounded()))s so far, "
            + "and still going in the background. No build and no reindex will speed this up, and nothing is "
            + "wrong: a large store takes a while to read the first time. The declarations below are complete; "
            + "callers, overrides and references are the part that needs it. Ask again in a moment."
    }
}

/// The build commands a missing index store is answered with, as text.
struct StoreRemedy {
    /// What opens the one build command a worktree with a `Package.swift` at its root is told.
    private static var packageBuildOpening: String {
        "build one with `\(ProductName.current.binary) run "
    }

    /// What follows that command's root flag.
    private static var packageBuildClosing: String {
        "-- swift build --build-tests`"
    }

    /// `--root <root> ` where a lookup's `root` is not the directory SwiftSure is running in, else nothing: run from there, the build commands would build the caller's checkout instead of the one the answer is about.
    ///
    /// Both paths are compared with symlinks resolved, and `root` is shell-quoted where it needs it. `currentDirectory` is a parameter so a test can stand in for the caller's directory; `nil` means the caller's directory is unknown (an MCP server's working directory is where its session started, not where the agent's shell has moved to), so the root is always named.
    static func rootFlag(root: URL?, currentDirectory: String?) -> String {
        guard let root else { return "" }
        if let currentDirectory {
            let named = root.standardizedFileURL.resolvingSymlinksInPath().path
            let running = URL(fileURLWithPath: currentDirectory).standardizedFileURL.resolvingSymlinksInPath().path
            if named == running {
                return ""
            }
        }
        return "--root \(TestRunRequest.shellQuoted(root.path)) "
    }

    /// The end of the shell word that starts at `start` in `text`, read as a shell reads the forms the quoting helper writes: the first space or `;` outside single quotes, where a backslash outside them escapes the next character and inside them nothing escapes; the end of the text when there is none.
    static func endOfShellWord(in text: String, from start: String.Index) -> String.Index {
        var index = start
        var quoted = false
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                quoted = character != "'"
            } else if character == "'" {
                quoted = true
            } else if character == "\\" {
                index = text.index(after: index)
                if index == text.endIndex {
                    break
                }
            } else if character == " " || character == ";" {
                break
            }
            index = text.index(after: index)
        }
        return index
    }

    /// The one build command a worktree with a `Package.swift` at its root is told.
    static func packageBuild(rootFlag: String) -> String {
        "\(packageBuildOpening)\(rootFlag)\(packageBuildClosing)"
    }

    /// The root flag a note's package build command carries (empty where it carries none), or `nil` where the note holds no such command.
    static func packageRootFlag(in note: String) -> String? {
        rootFlag(in: note, after: packageBuildOpening)
    }

    /// The root flag the build command that follows `opening` in a note carries (empty where it carries none), or `nil` where the note holds no such command.
    static func rootFlag(in note: String, after opening: String) -> String? {
        guard let start = note.range(of: opening),
              let closing = note.range(of: "-- swift build --build-tests", range: start.upperBound ..< note.endIndex)
        else { return nil }
        return String(note[start.upperBound ..< closing.lowerBound])
    }

    /// The build text for the tree at `root`: SwiftPM's command alone where a `Package.swift` sits at the root with no Xcode project or workspace beside it, else both forms (``buildCommand(rootFlag:)``).
    static func buildText(root: URL?, rootFlag: String) -> String {
        guard let root, hasPackageOnly(at: root) else { return buildCommand(rootFlag: rootFlag) }
        return "\(ProductName.current.binary) run \(rootFlag)-- swift build --build-tests"
    }

    private static func hasPackageOnly(at root: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else { return false }
        let entries = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return !entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Both ways to get a store: SwiftPM's command and `xcodebuild`'s, the latter narrowed to the host architecture.
    static func buildCommand(rootFlag: String) -> String {
        "\(ProductName.current.binary) run \(rootFlag)-- swift build --build-tests for a SwiftPM package at the root, or "
            + "\(ProductName.current.binary) run \(rootFlag)-- xcodebuild -scheme <Scheme> build (add -workspace <W>.xcworkspace when the "
            + "project has one) for a macOS project — an iOS project also needs -destination "
            + "'generic/platform=iOS Simulator' ARCHS=\(hostArchitecture)"
    }

    /// The architecture this binary is running on, for narrowing a simulator destination to the one slice that will ever execute (Docs/Design.md §2, `Distribution/make-dist.sh`'s own arm64-only build).
    private static let hostArchitecture: String = {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "arm64"
        #endif
    }()
}
