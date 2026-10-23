//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The stop-time validation gate: a context that edited Swift or another build input and is stopping on a tree no green `swift-sure run` stands for is sent back, once, to build it.
///
/// Whether the tree is validated is the question `swift-sure run --proved` asks — a ``RunLedger`` record whose ``TreeKey`` is the tree as it stands — widened to any command and to the checkout's ``RunLedger/greenBuilds(inCheckout:)``, where every green `swift-sure run` build or test records the tree it saw however the shell around it was written. The context's own transcript is the fallback, for a run no record reached: a green `swift-sure run` build or test after its last Swift edit, placed in its repository and vouched for by the call's result, answers it too. Every way the question cannot be put answers "no block": the gate is advice with teeth, and one that guessed would stop sessions on its own mistakes.
public struct StopBuildGate {
    /// How long the whole judgement may take before the stop goes through unremarked.
    public static let timeBudget: TimeInterval = 1

    /// When the process holding `pid` started, as the kernel records it, or `nil` where nothing holds it.
    public static func processStart(of pid: Int32) -> Date? {
        KernelProcess.startMicroseconds(of: pid).map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000_000) }
    }

    /// The reason to block this `Stop` or `SubagentStop` payload with, or `nil` where the stop goes through.
    ///
    /// Claimed in `marks` once per context and tree, so an agent sent back is never sent back twice for the same content, and `stop_hook_active` — a stop already continued by a hook — never blocks at all.
    ///
    /// `now` is the instant a run's start and heartbeat are judged against, and `processStart` when the process holding a pid started, or `nil` where none holds it.
    public static func reason(
        for payload: [String: Any],
        marks: ReuseNudgeMarks,
        now: Date = Date(),
        processStart: (Int32) -> Date? = processStart(of:)
    ) -> String? {
        guard payload["stop_hook_active"] as? Bool != true,
              let sessionID = payload["session_id"] as? String, !sessionID.isEmpty,
              let transcript = transcript(of: payload),
              let scan = BuildInputEditsSinceGreenRun.scan(transcript: transcript.url, skippingSidechains: !transcript.isSubagent)
        else {
            return nil
        }
        let context = AdviceContext.resolve(
            sessionID: sessionID,
            transcriptPath: payload["agent_transcript_path"] as? String ?? payload["transcript_path"] as? String,
            agentID: payload["agent_id"] as? String
        )
        for (root, files) in repositories(of: scan.files) {
            let rootURL = URL(fileURLWithPath: root)
            let repository = CanonicalPath.of(root)
            guard let tree = TreeKey.of(repositoryRoot: rootURL), !isValidated(tree, in: rootURL) else {
                continue
            }
            // A build or test going on in this checkout that started after the last edit, the one the context or a runner it handed the tree to is waiting on: its verdict lands on record when it ends, and the next stop judges it.
            // Nothing is claimed, so a red verdict is still advised on, and nothing is printed, since the only line this hook has blocks the stop. Where the edit carries no time, a run of this very tree stands in for one started after it.
            let going = RunProgressPaths.runs(inRepositoryAt: rootURL).filter { isGoing($0, at: now, processStart: processStart) }
            if going.contains(where: { run in scan.lastEditAt[repository].map { run.startedAt > $0 } ?? (run.tree == tree.value) }) {
                continue
            }
            let running = going
            guard let build = build(root: rootURL, xcodebuild: scan.xcodebuild, standingIn: scan.cwd, editing: files),
                  marks.claim(context: context.key, file: root, declaration: running.isEmpty ? "stop \(tree.value)" : "stop waiting \(tree.value)")
            else {
                continue
            }
            let why = scan.unconfirmedBuilds[repository]
            return running.isEmpty ? reason(edited: files, build: build, unconfirmed: why) : reason(edited: files, afterEarlierRunIn: build, unconfirmed: why)
        }
        return nil
    }

    /// ``command(root:xcodebuild:standingIn:editing:)``, or where it names none, the first platform an iOS-only package declares, or `nil` where there is nothing to ask for.
    static func build(root: URL, xcodebuild: (command: String, directory: String?)?, standingIn cwd: String?, editing files: [String] = []) -> Build? {
        if let named = command(root: root, xcodebuild: xcodebuild, standingIn: cwd, editing: files) {
            return .named(command: named.command, directory: named.directory)
        }
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return enclosingPackages(of: files, under: root).lazy.compactMap { ManifestPlatforms.firstWithoutMacOS(inPackageAt: $0) }.first.map { .unspelled(platform: $0) }
        }
        return ManifestPlatforms.firstWithoutMacOS(inPackageAt: root).map { .unspelled(platform: $0) }
    }

    /// The directories below `root` that hold a `Package.swift` and enclose an edited file, each file's nearest one, in path order.
    ///
    /// A file under no package adds none, and `root` itself is never one.
    static func enclosingPackages(of files: [String], under root: URL) -> [URL] {
        let top = CanonicalPath.of(root.path)
        var found: Set<String> = []
        var enclosing: [String: String?] = [:]
        for file in files {
            var directory = URL(fileURLWithPath: CanonicalPath.of(file)).deletingLastPathComponent().path
            var visited: [String] = []
            var package: String?
            while directory.hasPrefix(top + "/") {
                if let known = enclosing[directory] {
                    package = known
                    break
                }
                visited.append(directory)
                if FileManager.default.fileExists(atPath: directory + "/Package.swift") {
                    package = directory
                    break
                }
                directory = URL(fileURLWithPath: directory).deletingLastPathComponent().path
            }
            for seen in visited {
                enclosing[seen] = .some(package)
            }
            if let package {
                found.insert(package)
            }
        }
        return found.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// The build the block names, and the directory in the checkout it is about: the `xcodebuild … build` the context already ran, else `swift build` where a package sits at the root and does not leave macOS out, else, where the root holds no package, `swift build --package-path <dir>` for each package below it that encloses an edited file, else nothing.
    ///
    /// A package whose `platforms:` list names others and not macOS, an iOS-only one, is not built by `swift build` on this Mac, so it is named no command (see ``build(root:xcodebuild:standingIn:editing:)``); a manifest with no `platforms:` is taken to include macOS, and `.macCatalyst` is not macOS.
    ///
    /// Always a build, never a test, and never a command spelled here: a scheme and a destination are the project's to name, so an `xcodebuild` is only ever one the agent wrote itself, run in the directory it ran in, inside the checkout or not; where the line leaves that directory unknown, nothing is named, since a fragment of a line would build somewhere else. The ledger is not a source: it records test runs, and a test is more than the block asks for.
    ///
    /// Named bare where `cwd`, the directory the context stands in, is the one the build runs in, since only a bare command runs without asking in a session that asks about commands; anywhere else it is a subshell, `(cd <dir> && …)`, which runs it there without moving the caller's shell.
    ///
    /// The directory returned is the one the build runs in where that is inside the checkout, and the checkout's root otherwise.
    static func command(root: URL, xcodebuild: (command: String, directory: String?)?, standingIn cwd: String? = nil, editing files: [String] = []) -> (command: String, directory: String)? {
        let standing = cwd.map(CanonicalPath.of)
        if let xcodebuild, let directory = xcodebuild.directory {
            let canonicalRoot = CanonicalPath.of(root.path)
            let ranIn = CanonicalPath.of(directory)
            let shown = ranIn == canonicalRoot || ranIn.hasPrefix(canonicalRoot + "/") ? ranIn : root.path
            return (standing == ranIn ? xcodebuild.command : "(cd \(ShellWord.quoted(ranIn)) && \(xcodebuild.command))", shown)
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            return nested(root: root, standing: standing, editing: files)
        }
        guard ManifestPlatforms.firstWithoutMacOS(inPackageAt: root) == nil else {
            return nil
        }
        let build = "\(ProductName.current.binary) run -- swift build"
        return (standing == CanonicalPath.of(root.path) ? build : "(cd \(ShellWord.quoted(root.path)) && \(build))", root.path)
    }

    /// The build of each package below `root` that encloses an edited file, joined with ` && ` in path order, or `nil` where there is none or any of them leaves macOS out.
    ///
    /// A build that left an iOS-only package unbuilt would clear the repository's edits without it, so none is named and ``build(root:xcodebuild:standingIn:editing:)`` asks for the platform instead.
    ///
    /// Each is `swift build --package-path <dir>` with the directory relative to `root`, run from `root`, so a green run of it clears the repository's edits as a root build does.
    private static func nested(root: URL, standing: String?, editing files: [String]) -> (command: String, directory: String)? {
        let top = CanonicalPath.of(root.path)
        let packages = enclosingPackages(of: files, under: root)
        guard !packages.contains(where: { ManifestPlatforms.firstWithoutMacOS(inPackageAt: $0) != nil }) else {
            return nil
        }
        let builds = packages
            .map { "\(ProductName.current.binary) run -- swift build --package-path \(ShellWord.quoted(String($0.path.dropFirst(top.count + 1))))" }
        guard !builds.isEmpty else {
            return nil
        }
        let build = builds.joined(separator: " && ")
        return (standing == top ? build : "(cd \(ShellWord.quoted(root.path)) && \(build))", root.path)
    }
}

extension StopBuildGate {
    /// What the block asks for: a build spelled out, or one the project must name because `swift build` on this Mac may not build its package.
    enum Build {
        case named(command: String, directory: String)
        case unspelled(platform: String)
    }
}

private extension StopBuildGate {
    /// How many of the newest records of each ledger are compared with a tree no record names exactly, one `git diff-tree` apiece.
    static let nearRecordsCompared = 4

    /// Whether `run` is a build or a test still going by its process, started no longer than ``RunProgressSnapshot/processCeiling`` before `now`, by a process that `processStart` says started no later than the run did.
    ///
    /// The file names a tree only for a build or a test of its repository, so a run with none is some other kind. A pid the system has since reused belongs to a process started after the run, which the start time tells apart; the ceiling on the run's start bounds the rest. The run's start is written after its process began, to the millisecond, so a second's slack covers the rounding.
    static func isGoing(_ run: RunProgressSnapshot, at now: Date, processStart: (Int32) -> Date?) -> Bool {
        guard run.tree != nil, run.processIsGoingOn(at: now), now.timeIntervalSince(run.startedAt) <= RunProgressSnapshot.processCeiling,
              let started = processStart(run.pid)
        else {
            return false
        }
        return started <= run.startedAt.addingTimeInterval(1)
    }

    /// Whether a green record stands for `tree`: one of this very tree, or of one that differs from it only in files no build reads, such as a changelog edited and committed after the run.
    static func isValidated(_ tree: TreeKey, in root: URL) -> Bool {
        let ledgers = [RunLedger.inRepository(at: root), RunLedger.greenBuilds(inCheckout: root)].map { $0.records() }
        if ledgers.contains(where: { $0.contains { $0.tree == tree.value } }) {
            return true
        }
        return ledgers.flatMap { $0.prefix(nearRecordsCompared) }.contains {
            tree.sameSwiftSources(as: TreeKey(value: $0.tree), repositoryRoot: root)
        }
    }

    /// The repositories the edited files the index would take fall in, each with its files, the one edited last first.
    ///
    /// A file the index's inclusion rule keeps out, an ignored path or one under a build directory among them, is no edit, one outside every repository has none to build, and one no longer on disk — deleted, or checked out away with the branch that holds it — has nothing to build either.
    static func repositories(of edited: [String]) -> [(root: String, files: [String])] {
        var placed: [(file: String, root: String)] = []
        var filesByRoot: [String: [String]] = [:]
        for file in edited.reversed() {
            guard FileManager.default.fileExists(atPath: file),
                  let root = CallerRoot.root(forCallerIn: URL(fileURLWithPath: file).deletingLastPathComponent().path),
                  CanonicalPath.of(file).hasPrefix(CanonicalPath.of(root) + "/")
            else {
                continue
            }
            placed.append((file, root))
            filesByRoot[root, default: []].append(file)
        }
        // One ignore check a repository, not one a file.
        let coveredByRoot = Dictionary(uniqueKeysWithValues: filesByRoot.map { ($0.key, Set(EditParseCheck.covered($0.value, under: $0.key))) })
        var order: [String] = []
        var keptByRoot: [String: [String]] = [:]
        for (file, root) in placed where coveredByRoot[root]?.contains(file) == true {
            if keptByRoot[root] == nil {
                order.append(root)
            }
            keptByRoot[root, default: []].insert(file, at: 0)
        }
        return order.map { ($0, keptByRoot[$0] ?? []) }
    }

    /// The transcript of the context that is stopping, and whether it is a subagent's, or `nil` where the payload does not name one.
    ///
    /// A subagent's own file, never its parent's in its place: read as the subagent's, the parent's edits would block a subagent that made none.
    static func transcript(of payload: [String: Any]) -> (url: URL, isSubagent: Bool)? {
        guard payload["hook_event_name"] as? String == "SubagentStop" else {
            return (payload["transcript_path"] as? String).flatMap { $0.isEmpty ? nil : (URL(fileURLWithPath: $0), false) }
        }
        if let own = payload["agent_transcript_path"] as? String, !own.isEmpty {
            return (URL(fileURLWithPath: own), true)
        }
        guard let agent = payload["agent_id"] as? String, !agent.isEmpty,
              let session = payload["transcript_path"] as? String, !session.isEmpty,
              let own = ServerPresence.transcript(ofSession: session, agent: agent), own != session
        else {
            return nil
        }
        return (URL(fileURLWithPath: own), true)
    }

    /// What the model is told while a run of an earlier tree is going on in the checkout: which files it changed, that nothing has validated the tree they are in, and to run the build again once that run ends, never to start one beside it.
    ///
    /// A second build in the same `.build` collides with the live one, so the command is named for afterwards only.
    static func reason(edited: [String], afterEarlierRunIn build: Build, unconfirmed: (server: String, tool: String)? = nil) -> String {
        let head = opening(edited: edited, unconfirmed: unconfirmed)
        let tail = " (Asked once for this tree; \(EnvironmentVariable.noAdvice.name)=1 turns it off.)"
        let body = switch build {
        case let .named(command, directory):
            "A `\(ProductName.current.binary) run` of an earlier tree is in progress in \(directory); do not start another build beside it. "
                + "Once it ends, run `\(command)` again and fix what it reports before reporting done."
        case let .unspelled(platform):
            "A `\(ProductName.current.binary) run` of an earlier tree is in progress in this checkout; do not start another build beside it. "
                + "Once it ends, " + platformNote(platform)
        }
        return head + body + tail
    }

    /// What the model is told: which files it changed, that nothing has validated the tree they are in, and the one command that will, or for a package that leaves macOS out, what to build in its place.
    static func reason(edited: [String], build: Build, unconfirmed: (server: String, tool: String)? = nil) -> String {
        let head = opening(edited: edited, unconfirmed: unconfirmed)
        let tail = " (Asked once for this tree; \(EnvironmentVariable.noAdvice.name)=1 turns it off.)"
        let body = switch build {
        case let .named(command, _):
            "Run `\(command)` and fix what it reports before reporting done."
        case let .unspelled(platform):
            platformNote(platform)
        }
        return head + body + tail
    }

    /// The block's opening sentence: which files the context changed and that nothing has validated the tree they are in, with why a build made through another MCP server after the last edit did not, where one ran and its result carried neither a success line nor a failure line.
    static func opening(edited: [String], unconfirmed: (server: String, tool: String)?) -> String {
        let (files, shown) = summary(of: edited)
        let head = "\(ProductName.current.binary): you edited \(files) (\(shown)) and no green `\(ProductName.current.binary) run` build or test is on record for the tree as it stands"
        guard let unconfirmed else { return head + ". " }
        return head + "; a build ran through \(unconfirmed.server) \(unconfirmed.tool) after the last edit, but its result carries no success line. "
    }

    /// The ask for a package that leaves macOS out: why `swift build` is not it, and that the project's own simulator build is.
    static func platformNote(_ platform: String) -> String {
        "Package.swift declares \(platform) and not macOS, so `swift build` on this Mac may not build it. "
            + "Run the project's `xcodebuild … build` for a simulator destination through `\(ProductName.current.binary) run --` and fix what it reports before reporting done."
    }

    /// How many files the context changed, as a phrase, and the first three by name: Swift files where every one is Swift, build inputs once any is not.
    static func summary(of edited: [String]) -> (files: String, shown: String) {
        let names = edited.map { URL(fileURLWithPath: $0).lastPathComponent }
        let shown = names.count > 3 ? names.prefix(3).joined(separator: ", ") + ", …" : names.joined(separator: ", ")
        let kind = names.allSatisfy { $0.hasSuffix(".swift") } ? "Swift file" : "build input"
        return ("\(edited.count) \(kind)\(edited.count == 1 ? "" : "s")", shown)
    }
}
