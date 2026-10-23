//
// Copyright © Agulhas Labs
//

import Foundation

/// Under `--refs`, the Swift files of the test targets no store holds a unit for, searched by written name: what a sweep's reader would otherwise grep for once told that references from tests are a lower bound.
///
/// A test target is a module holding a test file (``TestFileRecognition``, by import), so its helpers that import no test framework are read too. It runs only where some test file has no unit, the targets never built or some files left out: where the store holds every test file its answer is complete, and with no store at all the by-name sweep already reads the whole tree. The scan is ``WhereUnbuiltMentions``'s, capped at ``WhereUnbuiltMentions/scanCap`` files with the rest that hold the name counted as not scanned, and its mentions are what the `not in the build, mention the name:` line lists. Where none writes the name the answer says so (``clause``) in place of the advice to build the tests, with the Objective-C files beside them, which are not read, counted as a gap declared.
struct WhereTestTargetScan {
    /// The repo-relative Swift files searched, sorted.
    let paths: [String]
    /// The mentions found and the files holding the name past the cap, which were not lexed.
    let scanned: (mentions: [NameMention], unscanned: Int)
    /// The `.m` and `.mm` files in the directories holding those Swift files, which are not read.
    let objectiveCFiles: Int

    /// Whether no file searched writes the name.
    var foundNone: Bool {
        scanned.mentions.isEmpty && scanned.unscanned == 0
    }

    /// `; none of the 3 Swift files in test targets writes the name; 1 Objective-C test file not read`, the clause that replaces the advice to build the tests, or `nil` where a file writes the name.
    var clause: String? {
        result.map { "; " + $0 }
    }

    /// The result without the leading `; `, or `nil` where a file writes the name.
    var result: String? {
        guard foundNone else { return nil }
        let objectiveC = objectiveCFiles == 0 ? "" : "; \(objectiveCFiles) Objective-C test file\(objectiveCFiles == 1 ? "" : "s") not read"
        let searched = paths.count == 1
            ? "the 1 Swift file in test targets does not write the name"
            : "none of the \(paths.count) Swift files in test targets writes the name"
        return searched + objectiveC
    }

    /// Whether ``stating(in:)`` put the result in a usage tally, which then carries it, so it is not repeated on a line of its own.
    private(set) var tallied = false

    /// `lines` with each usage tally's hedged tests entry stating this scan's result in place of its reason, `0 tests (none of the 2 Swift files in test targets writes the name)`; unchanged where a file writes the name.
    ///
    /// The tally is written before the scan runs, so the reason it gave, the advice to build the tests, is replaced here, and the result is then said once.
    mutating func stating(in lines: [String]) -> [String] {
        guard let result else { return lines }
        // A usage tally's tests entry, `tests not counted (…)` or `N tests, a lower bound (…)`, whose parenthesis holds no parenthesis of its own.
        let testsEntry = /(?:tests not counted|(\d+) tests?, a lower bound) \([^()]*\)/
        var replaced = false
        let stated = lines.map { line in
            line.replacing(testsEntry) { match in
                replaced = true
                return "\(match.1 ?? "0") tests (\(result))"
            }
        }
        tallied = tallied || replaced
        return stated
    }

    /// The result on a line of its own, blank line first, for an answer that lists references and so has no empty verdict to carry it in its hedge; nothing where one does, where a tally states it, or where a file writes the name.
    func ownLine(besideEmptyVerdicts: Bool) -> [String] {
        guard !besideEmptyVerdicts, !tallied, let result else { return [] }
        return ["", result]
    }

    /// The scan of every Swift file without a unit in a module of `index` that holds a test file for `names`, or `nil` where every test file has a unit or there is no name to search for.
    init?(names: ScannedNames, in index: IndexStore, context: SemanticContext) throws {
        guard !names.isEmpty else { return nil }
        let files = try index.fileInventory().values
        let testFiles = files.filter { TestFileRecognition.isTestFile(imports: $0.imports) }
        guard testFiles.contains(where: { !context.anyStoreHasUnit(forFile: $0.path) }) else { return nil }
        let testModules = Set(testFiles.map(\.module))
        paths = files.filter { testModules.contains($0.module) && !context.anyStoreHasUnit(forFile: $0.path) }.map(\.path).sorted()
        let rootPath = context.repoRoot.path
        scanned = WhereUnbuiltMentions.mentionScan(of: names, in: paths, under: rootPath, lexCap: WhereUnbuiltMentions.scanCap)
        objectiveCFiles = Self.objectiveCFiles(beside: paths, under: rootPath)
    }

    /// The `.m` and `.mm` files directly in the directories holding `paths`; a subdirectory is read only where it holds a Swift file of its own.
    private static func objectiveCFiles(beside paths: [String], under rootPath: String) -> Int {
        let directories = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        return directories.reduce(0) { count, directory in
            let url = directory.isEmpty ? URL(fileURLWithPath: rootPath) : URL(fileURLWithPath: rootPath).appendingPathComponent(directory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return count + names.count { ["m", "mm"].contains(($0 as NSString).pathExtension) }
        }
    }
}
