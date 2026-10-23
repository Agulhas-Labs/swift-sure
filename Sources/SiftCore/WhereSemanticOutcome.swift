//
// Copyright © Agulhas Labs
//

extension WhereRenderer {
    /// What the semantic pass produced: the axis for the header, the declarations it could not answer for, which the syntactic fallback then picks up, and what it listed.
    struct SemanticOutcome {
        let axis: SemanticAxis
        let refused: [SymbolRow]
        /// The note under the header naming the modules a later build left out, where the answer cites rows in their changed files (``NotCompiledNote``).
        var notCompiledNote: String?
        /// The in-tree stores that owned at least one declaration, by name, in the order they first answered.
        var answeredBy: [String] = []
        /// The declarations no store resolved, for the line naming the project that builds their files.
        var uncovered: [SymbolRow] = []
        /// The name-matched sites already listed beside the store's answers, which the syntactic fallback lists no second time.
        var listedSites: [SyntacticCallSite] = []
        /// The repo-relative `path:line:column` of every call the store's answers listed on a line of its own, where the store records a call, never one only counted in a fold or past the cap.
        var recordedCalls: Set<String> = []
        /// The repo-relative `path:line:column` of every type use a type's or typealias's answer handed on, in a file unchanged since the build, at the column its name is written: `true` where it listed the use on a line of its own, `false` where it only counted it with a pointer to `--refs`.
        var typeUses: [String: Bool] = [:]
        /// Each protocol's one conformers block, by name, which replaces the block the scan by written name would print for it.
        var conformerBlocks: [String: ConformersOnce] = [:]
        /// Each type's store check on the rows its block by written name walks to, by name, for a type that block is printed for.
        var writtenNameChecks: [String: WrittenNameCheck] = [:]
        /// Each refusal line the answer printed, by the line, with the words it takes where an answer by written name follows.
        var refusalWordings: [String: String] = [:]
        /// How many files the answer lists by written name that the store holds no unit for.
        var listedFileCount = 0

        /// Whether a type use of a refused declaration's name is one the store resolved, and listed above, as another declaration's.
        func listsTypeUse(_ site: SyntacticCallSite) -> Bool {
            site.nameAt.map { typeUses["\(site.path):\($0)"] != nil } ?? false
        }

        /// Whether it was listed on a line of its own there, rather than only counted.
        func listsTypeUseInPlace(_ site: SyntacticCallSite) -> Bool {
            site.nameAt.map { typeUses["\(site.path):\($0)"] == true } ?? false
        }

        /// Whether `site` is already listed above the syntactic fallback: as a name-matched site beside a store's answer, or as a call the store recorded at the name it is made through, which for a wrapper's attribute is the type's name.
        ///
        /// A recorded position is trusted only while its file is unchanged since the build, because after an edit the same line and column can hold a different call.
        func listsAlready(_ site: SyntacticCallSite, modifiedSinceBuild: (String) -> Bool) -> Bool {
            if listedSites.contains(where: { $0.isSamePlace(as: site) }) {
                return true
            }
            guard let calleeAt = site.calleeAt, !modifiedSinceBuild(site.path) else { return false }
            return recordedCalls.contains("\(site.path):\(calleeAt)")
        }
    }

    /// The heading clauses that disown part of what the section is nevertheless listing, changed before deleted as the header orders them — never omitted when they apply, since a count that silently includes dead rows is the defect this whole path exists to end.
    ///
    /// Counted in **files**, whatever the section lists, and worded identically in both: the header's own count is in files, and two sections disowning in different units invite the reader to compare numbers that were never the same measurement. One `states` entry per distinct file is the caller's job.
    static func driftDetails(states: [OccurrenceState]) -> [String] {
        var details: [String] = []
        let deleted = states.count { $0 == .deleted }
        let modified = states.count { $0 == .modifiedSinceBuild }
        if modified > 0 {
            details.append("\(modified) file\(modified == 1 ? "" : "s") changed since last build")
        }
        if deleted > 0 {
            details.append("\(deleted) file\(deleted == 1 ? "" : "s") deleted since last build")
        }
        return details
    }

    /// What a use inside an observer a macro moved cannot show — where it is written — stated wherever one is listed: its row sits on the macro's line, and a reference sweep drops it, since there is nothing to rename there.
    static var movedObserverBoundary: String {
        "observers: a macro that moves a property into generated storage, as @Observable does, moves its didSet and willSet with it — the store records their uses at the macro's line, never where they are written, so a reference sweep lists none of their lines"
    }
}
