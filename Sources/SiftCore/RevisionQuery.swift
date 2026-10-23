//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// `digest --at` and `where --at`: a question asked of a past revision's tree, answered syntactically from a transient parse of only the files that could bear on it.
///
/// The renderers are the working tree's own, pointed at a ``RevisionSnapshot`` instead of the store, so an answer about a revision reads exactly as one about the working tree does — under a header that names the revision and says it is syntactic, and a line counting the files parsed.
struct RevisionQuery {
    let repoRoot: URL
    let tree: WorkingTree
    let git: GitContext
    let enumerator: FileEnumerator
    let resolver: ModuleResolver
    let config: SiftConfig
    let revision: String

    /// What the semantic half of a `where --at` answer says in place of the store, which describes the working tree and so nothing at a past revision.
    static var semanticNote: String {
        "semantic not consulted (--at reads a past revision; the build's index store describes the working tree)"
    }

    /// The declaration surface of each target as of the revision; a module, `.` or a `.md` target is refused, since none of them is answerable from a few files.
    func digest(targets: [String], options revisionless: DigestOptions) throws -> String {
        var options = revisionless
        options.servesModules = false
        let files = try RevisionSnapshot.indexableFiles(revision: revision, git: git, enumerator: enumerator)
        let moduleNames = Self.moduleNames(for: files.paths, resolver: resolver)
        let written = targets.map { relativeTarget($0, among: files.paths) }
        var paths: [String] = []
        var names: [String] = []
        var bareModules: [String] = []
        for target in written {
            if let refusal = refusal(forDigestTarget: target, moduleNames: moduleNames, paths: files.paths) {
                throw EngineError.revisionRefused(refusal)
            }
            if moduleNames.contains(target) {
                bareModules.append(target)
            }
            if let range = DigestLineRange.parse(target) {
                paths.append(range.path)
            } else if target.contains("/") || target.hasSuffix(".swift") {
                paths.append(target)
            } else {
                names += searchNames(for: target, moduleNames: moduleNames)
            }
        }
        if written.count == 1, paths.count == 1, names.isEmpty,
           let notice = try excludedFileNotice(target: paths[0], commit: files.commit)
        {
            return try header(commit: files.commit) + "\n" + notice
        }
        // A path target excluded from today's index answers with the same notice inside a multi-target digest, rather than falling to the renderer's own "no indexed file" miss, which knows nothing about the revision or why the file is out.
        var notices: [String: String] = [:]
        for path in paths {
            if let notice = try excludedFileNotice(target: path, commit: files.commit) {
                notices[path] = notice
            }
        }
        let snapshot = try read(files: files, selecting: { path in paths.contains { Self.path(path, answers: $0) } }, naming: names)
        defer { snapshot.discard() }
        // A bare name that is a module serves the type of that name where there is one, as in the working tree; with none it is the module, which a few files cannot answer.
        for name in bareModules where try snapshot.store.typeDeclarations(named: name).isEmpty {
            throw EngineError.revisionRefused(Self.refusal(of: name, as: "a module", revision: revision))
        }
        var renderer = DigestRenderer(store: snapshot.store, moduleNames: moduleNames, repoRoot: snapshot.root)
        renderer.config = config
        renderer.isUnreadablyRenamed = { [resolver] in resolver.isUnreadablyRenamed($0) }
        renderer.revision = WhereBasenamePointer.Revision(name: revision, paths: files.paths)
        let rendered: String
        if notices.isEmpty {
            rendered = try renderer.render(targets: written, options: options)
        } else {
            if written.count > 1, options.offset != 0 {
                throw EngineError.offsetWithSeveralTargets(count: written.count)
            }
            let bodies = try written.map { target -> String in
                try notices[target] ?? renderer.render(targets: [target], options: options)
            }
            rendered = DigestRenderer.joinedAnswers(bodies)
        }
        let body = rendered.replacingOccurrences(
            of: #"(no symbol named \S+) in the index"#,
            with: "$1 \(missedAtRevision(snapshot))",
            options: .regularExpression
        )
        return try header(snapshot) + "\n" + readLine(snapshot, names: names, files: paths) + "\n" + body
    }

    /// Why a target answerable only as a file cannot be, when the file is real at the revision but excluded from the index today — read straight from the target's tracked path rather than a miss the snapshot's already-filtered candidates could never explain.
    ///
    /// A target written as a bare file name can match more than one tracked path (``path(_:answers:)`` falls back to matching by name alone); an exact — or suffix-exact — match is preferred over that fallback, so a target naming one file is never excused, or answered, by an unrelated file of the same name. And the notice fires only when every file that could answer the target is excluded: one that is not means the target is served normally.
    private func excludedFileNotice(target: String, commit: String) throws -> String? {
        let tree = try git.trackedEntries(at: commit)
        let modes = FileEnumerator.Modes.revision(links: tree.links)
        let matches = tree.paths.filter { Self.path($0, answers: target) }
        guard !matches.isEmpty else { return nil }
        let exact = matches.filter { $0 == target || $0.hasSuffix("/" + target) }
        let candidates = exact.isEmpty ? matches : exact
        guard candidates.allSatisfy({ enumerator.exclusion(of: $0, modes: modes) != nil }), let matched = candidates.first, let exclusion = enumerator.exclusion(of: matched, modes: modes) else { return nil }
        let clause = switch exclusion {
        case .configExclude, .outsideRoots:
            "today's config excludes it (\(exclusion.reason))"
        default:
            "is excluded: \(exclusion.reason)"
        }
        return "\(matched) exists at \(commit.prefix(8)) but \(clause)"
    }

    /// The clause a miss earns in place of "in the index" — the store the working tree misses against, which a revision has none of — naming the revision and what parsing it cost instead.
    private func missedAtRevision(_ snapshot: RevisionSnapshot) -> String {
        let noun = snapshot.candidates == 1 ? "file" : "files"
        return "at \(snapshot.commit.prefix(8)) — parsed \(snapshot.paths.count) of \(snapshot.candidates) Swift \(noun) naming it"
    }

    /// The symbol's declarations as of the revision, with call sites matched by name in that revision's files — never the store's callers.
    func lookup(symbol: String, options: WhereOptions) async throws -> String {
        let files = try RevisionSnapshot.indexableFiles(revision: revision, git: git, enumerator: enumerator)
        let moduleNames = Self.moduleNames(for: files.paths, resolver: resolver)
        let names = searchNames(for: symbol, moduleNames: moduleNames)
        // An initializer is also called as `Self(x)` in an extension of a protocol, in a file spelling neither its type nor `init`.
        let isInitializer = names.first == "init"
        let snapshot = try read(files: files, selecting: { _ in false }, naming: names, spelling: { isInitializer && SelfCallSpelling.isWritten(in: $0) })
        defer { snapshot.discard() }
        let listing = FileEnumerator(repoRoot: snapshot.root, config: config, gitListing: { snapshot.paths })
        let scanner = CallSiteScanner(repoRoot: snapshot.root, enumerator: listing, readsProtocolBuiltBodies: true)
        var renderer = WhereRenderer(store: snapshot.store, callSites: { await scanner.callSites(named: $0) })
        renderer.revision = revision
        renderer.revisionPaths = files.paths
        renderer.usesFileCount = { [snapshot] name in await WhereUsesPointer.fileCount(of: name, repoRoot: snapshot.root, enumerator: listing) }
        renderer.isUnreadablyRenamed = { [resolver] in resolver.isUnreadablyRenamed($0) }
        var syntactic = options
        syntactic.includeSemantic = false
        let output = try await renderer.render(query: symbol, semantic: .inactive(note: Self.semanticNote), options: syntactic)
        return try header(snapshot) + "\n" + readLine(snapshot, names: names, files: [], spellingSelfCalls: isInitializer) + "\n" + output.body
    }

    private func read(files: (commit: String, paths: [String]), selecting: (String) -> Bool, naming names: [String], spelling: (Data) -> Bool = { _ in false }) throws -> RevisionSnapshot {
        try RevisionSnapshot.read(
            revision: revision,
            files: files,
            git: git,
            resolver: resolver,
            selecting: selecting,
            naming: names,
            spelling: spelling
        )
    }

    /// The header: the tree, and the revision in place of `head:` — with the commit it resolved to where the revision was not written as one, and a note that the working tree differs only where the revision named is `HEAD`'s own commit and the tree is dirty.
    ///
    /// Any other revision gets no such note: the answer is about that commit whatever the tree holds.
    private func header(_ snapshot: RevisionSnapshot) throws -> String {
        try header(commit: snapshot.commit)
    }

    /// The header built from the commit alone, for an answer that never builds a ``RevisionSnapshot`` at all.
    private func header(commit: String) throws -> String {
        let named = commit.hasPrefix(revision) ? revision : "\(revision) = \(commit.prefix(8))"
        let isDirtyHead = try git.head() == commit && !git.dirtyFiles().isEmpty
        let note = isDirtyHead ? "; the working tree differs" : ""
        return "\(WorkingTree.fieldOpening)\(tree.rendered)\(WorkingTree.fieldSeparator)at: \(named) (syntactic, from git\(note))"
    }

    /// What the answer cost to build: how many of the revision's Swift files were parsed, and what chose them, and where asked that files spelling a `Self(x)` call were read too, as an initializer's sweep reads them.
    private func readLine(_ snapshot: RevisionSnapshot, names: [String], files: [String], spellingSelfCalls: Bool = false) -> String {
        var chosenBy: [String] = []
        if !names.isEmpty {
            chosenBy.append("naming " + names.map { "`\($0)`" }.joined(separator: " or "))
        }
        if spellingSelfCalls {
            chosenBy.append("spelling `Self(`")
        }
        if !files.isEmpty {
            chosenBy.append("at " + files.map { "`\($0)`" }.joined(separator: " or "))
        }
        let noun = snapshot.candidates == 1 ? "file" : "files"
        return "read: parsed \(snapshot.paths.count) of \(snapshot.candidates) Swift \(noun) at \(snapshot.commit.prefix(8)) — those "
            + chosenBy.joined(separator: " or ")
    }

    /// The names a file must spell to bear on `target`: its final component, and the container written just before it unless that is a module.
    private func searchNames(for target: String, moduleNames: [String]) -> [String] {
        var components = QualifiedPath.components(of: target)
        if components.count > 1, moduleNames.contains(components[0]) {
            components.removeFirst()
        }
        let bases = components.suffix(2).map { QualifiedPath.baseName(of: $0) }
        var names: [String] = []
        for base in bases.reversed() where !names.contains(base) {
            names.append(base)
        }
        return names
    }

    /// Why a digest target cannot be answered at a revision, or `nil` when it can.
    private func refusal(forDigestTarget target: String, moduleNames: [String], paths: [String]) -> String? {
        let subject: String
        if target == "." {
            subject = "the repository overview"
        } else if MarkdownOutline.names(target) {
            subject = "a document"
        } else if target.hasSuffix("/"), moduleNames.contains(SymbolNaming.unbackticked(String(target.dropLast()))) {
            subject = "a module"
        } else if target.contains("/"), !target.hasSuffix(".swift"), DigestModuleDirectory.module(of: String(target.hasSuffix("/") ? target.dropLast() : target[...]), files: paths.map { (path: $0, module: resolver.module(for: $0)) }) != nil {
            subject = "a module's directory"
        } else {
            return nil
        }
        return Self.refusal(of: target, as: subject, revision: revision)
    }

    private static func refusal(of target: String, as subject: String, revision: String) -> String {
        "digest --at answers a type, a member or a Swift file, and `\(target)` is \(subject) — ask it of a checkout of \(revision) (`git worktree add`)"
    }

    /// The revision's modules, resolved the way the working-tree indexer resolves them — per file, through the module resolver — never from the (possibly absent or stale) index store.
    private static func moduleNames(for paths: [String], resolver: ModuleResolver) -> [String] {
        Array(Set(paths.map(resolver.module(for:)))).sorted()
    }

    /// A path target made repo-relative and spelled as the revision spells it, without asking the working tree's filesystem, which may have moved, renamed or symlinked what the revision holds.
    ///
    /// An absolute path under the repository loses its root, a leading `./` goes and `.` and `..` segments resolve lexically. The result is used exactly when it names one of the revision's own files or directories; otherwise a case-insensitive match among them is used when it is unique, and an ambiguous one leaves the target as typed. A trailing slash survives, since it is what marks a module's name. A name with no slash is left alone.
    private func relativeTarget(_ target: String, among paths: [String]) -> String {
        guard target.contains("/") else { return target }
        var relative = target
        if target.hasPrefix("/") {
            let roots = [repoRoot.path, repoRoot.standardizedFileURL.path, CanonicalPath.of(repoRoot.path)]
            guard let root = roots.first(where: { target.hasPrefix($0 + "/") }) else { return target }
            relative = String(target.dropFirst(root.count + 1))
        }
        var segments: [Substring] = []
        for segment in relative.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." {
                continue
            }
            if segment == "..", !segments.isEmpty, segments.last != ".." {
                segments.removeLast()
            } else {
                segments.append(segment)
            }
        }
        let suffix = target.hasSuffix("/") ? "/" : ""
        let lexical = segments.joined(separator: "/")
        var known = Set(paths)
        for path in paths {
            var parent = path
            while let slash = parent.lastIndex(of: "/") {
                parent = String(parent[..<slash])
                if !known.insert(parent).inserted {
                    break
                }
            }
        }
        if known.contains(lexical) {
            return lexical + suffix
        }
        let matches = known.filter { $0.caseInsensitiveCompare(lexical) == .orderedSame }
        if matches.count == 1, let only = matches.first {
            return only + suffix
        }
        return matches.isEmpty ? lexical + suffix : target
    }

    /// Whether a file at `path` could answer a file target written as `asked` — exactly, as a suffix on a directory boundary, or by its file name, which the digest's own fallback serves.
    private static func path(_ path: String, answers asked: String) -> Bool {
        path == asked || path.hasSuffix("/" + asked) || (path as NSString).lastPathComponent == (asked as NSString).lastPathComponent
    }
}
