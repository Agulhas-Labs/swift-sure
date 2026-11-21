//
// Copyright © Agulhas Labs
//

import Foundation

/// The line `swift-sure run` adds under a `swift test --filter` run on a changed tree: the suites that reach the uncommitted change and that the filter left out, so a reader does not take the filter's failures for the whole set.
///
/// A note, as ``UnmatchedFilterHint`` is: it never changes the totals, the verdict, the exit code or what the run records, and it is left out wherever it cannot be made cheaply and honestly.
public struct FilteredRunReachHint: Sendable, Equatable {
    /// The uncommitted files, as paths from the root.
    let files: [String]
    /// The reaching suites the run left out or ran in part, nearest first.
    let suites: [Suite]

    /// How many suites the line names before it counts the rest.
    static let listedSuites = UnmatchedFilterHint.listedSuites

    /// How long finding the suites may take before the line is left out rather than waited on.
    public static let lookupBudget = UnmatchedFilterHint.lookupBudget

    /// How many ids a green filtered run may file in the ledger for later runs to count; a longer run files none, so the ledger's records stay small.
    public static let recordedIdentifierLimit = 500

    /// The line a run owes when it left suites out that earlier runs on this tree covered: every reaching suite has passed, counting `covering` earlier runs.
    static func coveredLine(covering: Int) -> String {
        "  filtered: every suite reaching the change has passed on this tree (this run and \(covering) earlier run\(covering == 1 ? "" : "s"))"
    }

    /// The line, indented as the answer's other notes are, or `nil` where every reaching suite ran in full.
    var line: String? {
        guard let first = files.first, !suites.isEmpty else { return nil }
        let changed = files.count > 1 ? "\((first as NSString).lastPathComponent) and \(files.count - 1) more files" : (first as NSString).lastPathComponent
        let listed = suites.prefix(Self.listedSuites)
        let rest = suites.count - listed.count
        let partial = listed.filter { $0.ran > 0 }.map(\.described)
        let tests = suites.filter { $0.testName != nil }.count
        let counted = [(suites.count - tests, "suite"), (tests, "test")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: " and ")
        let verdict = partial.isEmpty ? "did not run" : "did not run in full: \(partial.joined(separator: ", "))"
        // Only the suites to add: the run's own filters already ran, and repeating them was most of the line.
        let command = listed.map(\.filter).map { "--filter " + TestRunRequest.shellQuoted($0) }.joined(separator: " ")
        let more = rest > 0 ? "+\(rest) more; " : ""
        return "  filtered: the working tree changes \(changed); \(counted) reaching it \(verdict) — run swift test \(command) (\(more)\(ProductName.current.binary) affected lists every suite)"
    }

    /// The suites of `reached` the run left out or ran in part, given `ran`, the ids the run ran.
    ///
    /// A suite whose every declared test is compiled out on this platform is left out of the answer. A suite counts as run only when every test the index declares in it reported. Where the index declares none, the suite ran when some id sits below it and did not otherwise.
    static func leftOut(_ reached: [AffectedRenderer.ReachedSuite], inventory: [DeclaredTest], ran: Set<String>) -> [Suite] {
        var declared: [String: [String]] = [:]
        var compiledOut: Set<String> = []
        for test in inventory {
            let base = TestSymbol(declared: test)
            let symbol = TestSymbol(target: TestIdentifier.moduleName(ofTarget: test.target), suite: base.suite, function: base.function, style: base.style)
            let key = symbol.suite == nil ? symbol.swiftTestFilter : symbol.suiteOnly.described
            if case .compiledOut = test.compilation {
                compiledOut.insert(key)
            } else {
                declared[key, default: []].append(symbol.described)
            }
        }
        return reached.compactMap { suite in
            func reported(_ name: String) -> Bool {
                ran.contains { $0 == name || $0.hasPrefix(name + "/") }
            }
            guard let names = declared[suite.filter] else {
                // A suite every test of which is compiled out here can never run: neither counted nor named.
                if compiledOut.contains(suite.filter) {
                    return nil
                }
                return reported(suite.filter) ? nil : Suite(filter: suite.filter, ran: 0, declared: 0, testName: suite.testName)
            }
            let count = names.filter(reported).count
            return count == names.count ? nil : Suite(filter: suite.filter, ran: count, declared: names.count, testName: suite.testName)
        }
    }

    /// The lines a filtered run on a changed tree owes: empty for every run that does not meet the design's conditions, so a run pays nothing for them.
    ///
    /// `earlier` holds the ids earlier green filtered runs of this tree ran, one array per run: a suite they covered is not named, and where they cover every suite this run left out the line says so.
    ///
    /// It needs a `swift test` that carried a `--filter`, whose own answer is not a refusal or a failed build, and that shows what it ran on the evidence ``RunTestSelector/ranIdentifiers(_:)`` asks for.
    public static func lines(after outcome: RunOutcome, selector: RunTestSelector?, repositoryRoot: URL?, budget: TimeInterval = lookupBudget, earlier: [[String]] = []) -> [String] {
        guard let report = outcome.report, let selector, !selector.patterns.isEmpty, let repositoryRoot, outcome.stoppedTest == nil,
              selector.ownExitCode(report, exitCode: outcome.exitCode) == nil,
              let ran = selector.ranIdentifiers(report)
        else {
            return []
        }
        let database = SiftPaths.cache(in: repositoryRoot).appendingPathComponent(SiftPaths.indexFileName)
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        let passed = outcome.exitCode == 0
        let box = HintBox()
        let finished = DispatchSemaphore(value: 0)
        let lookup = Task.detached {
            do {
                let engine = try SiftEngine(directory: repositoryRoot)
                // A store with no cache is never opened here, since its import alone can fill the budget, and the walk goes by
                // written name instead (``SiftEngine/opensColdStore``). One with a cache gets half the budget to reopen, so an
                // import of a rebuild's new units that runs long leaves the walk the other half rather than none.
                engine.opensColdStore = false
                engine.openBudget = budget / 2
                // Brought up to date first, inside the same budget: an index that has not seen the dirty files (after `search` alone it knows none) names no suite.
                try await engine.ensureFresh()
                if let (files, reached) = try await engine.suitesReachingWorkingTree() {
                    let inventory = try TestInventory.read(store: engine.store, repositoryRoot: repositoryRoot).tests
                    let own = leftOut(reached, inventory: inventory, ran: ran)
                    let union = earlier.reduce(into: ran) { $0.formUnion($1) }
                    let all = earlier.isEmpty ? own : leftOut(reached, inventory: inventory, ran: union)
                    if !own.isEmpty, all.isEmpty {
                        // A red run is never told every suite passed, and with nothing owed it has no line.
                        let covering = earlier.filter { leftOut(reached, inventory: inventory, ran: ran.union($0)) != own }.count
                        box.store(passed ? [coveredLine(covering: covering)] : [])
                    } else {
                        box.store(FilteredRunReachHint(files: files, suites: all).line.map { [$0] } ?? [])
                    }
                }
            } catch {
                box.store([])
            }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + budget) == .success else {
            lookup.cancel()
            return []
        }
        return box.value
    }
}

extension FilteredRunReachHint {
    /// A suite reaching the change that the run did not run in full.
    struct Suite: Equatable {
        /// The suite as `--filter` takes it.
        let filter: String
        /// How many of the suite's declared tests reported; `0` for a suite that did not run.
        let ran: Int
        /// How many tests the index declares in it, `0` where it declares none.
        let declared: Int
        /// The readable `Target.function()` where the entry is a test declared at file scope, not a suite.
        var testName: String?

        /// The entry as the line names it: its share too where it ran in part.
        var described: String {
            let name = testName ?? filter
            return ran > 0 ? "\(name) (\(ran) of \(declared) ran)" : name
        }
    }
}

private extension FilteredRunReachHint {
    final class HintBox: @unchecked Sendable {
        private(set) var value: [String] = []

        func store(_ lines: [String]) {
            value = lines
        }
    }
}
