//
// Copyright © Agulhas Labs
//

import Foundation

/// Gathers `diff`'s access section: for each declaration the range put at `open`, `public` or `package`, whether it is judged at all, and where it is used.
///
/// Uses are resolved by the index store where it can answer for the declaration's file, each use's module being the one its unit compiled, and name-matched in the files the store does not cover as they stand; otherwise they are name-matched over the working tree. A match's module is the one its path resolves to, and a path that resolves to none counts as outside. At most ``lookupCap`` declarations are looked up per answer, in the order the declarations section lists them, a declaration counting once any question about it is put to the index.
struct AccessLookup {
    let store: IndexStore
    let repoRoot: URL
    let enumerator: FileEnumerator
    let resolver: ModuleResolver

    /// Declarations looked up per answer before the rest are counted as not checked.
    static var lookupCap: Int {
        50
    }

    func report(for subjects: [AccessSubject], semantic: SemanticInput) async throws -> AccessReport? {
        var report = AccessReport()
        let witnesses = AccessWitnesses(store: store)
        var looked: [(subject: AccessSubject, usr: String?)] = []
        var lookups = 0
        for subject in subjects {
            // Any question put to the index about a declaration spends its place in the budget: whether an enclosing type caps it, its symbol, whether it is a witness. A declaration excluded by what is written, with no enclosing type to ask about, costs nothing.
            if subject.exclusion == nil || !subject.extendedTypes.isEmpty {
                guard lookups < Self.lookupCap else {
                    report.notChecked += 1
                    continue
                }
                lookups += 1
            }
            guard try isSubject(subject) else { continue }
            if let exclusion = subject.exclusion {
                report.notJudged[exclusion, default: 0] += 1
                continue
            }
            let usr = try storeSymbol(for: subject, semantic: semantic)
            let isWitness = if let usr, let context = semantic.context {
                !context.store.implementedRequirements(ofUSR: usr).isEmpty
            } else {
                try witnesses.mayBeWitness(subject)
            }
            if isWitness {
                report.notJudged[.witness, default: 0] += 1
                continue
            }
            looked.append((subject, usr))
        }
        guard !looked.isEmpty || !report.notJudged.isEmpty || report.notChecked > 0 else { return nil }
        report.findings = try await findings(for: looked, semantic: semantic)
        return report
    }
}

private extension AccessLookup {
    /// Whether the declaration is still one at those levels once every extended type the index declares caps it.
    func isSubject(_ subject: AccessSubject) throws -> Bool {
        for name in subject.extendedTypes {
            let declared = try store.typeDeclarations(named: name)
            if !declared.isEmpty, declared.allSatisfy({ !AccessSubjectCollector.judgedLevels.contains(min(subject.level, $0.accessLevel)) }) {
                return false
            }
        }
        return true
    }

    /// The declaration's symbol in the index store, where the store answers for its file as it stands: `nil` sends it to name matching.
    func storeSymbol(for subject: AccessSubject, semantic: SemanticInput) throws -> String? {
        guard case let .active(context) = semantic else { return nil }
        let rows = try store.symbols(named: subject.name).filter { $0.path == subject.path && $0.line == subject.line }
        guard rows.count == 1, let row = rows.first, context.packagesPassingOver(file: row.path) == nil else { return nil }
        let freshness = OccurrenceFreshness(store: store, context: context, projectDirectories: resolver.projectDirectories, citedBy: context.store)
        switch freshness.kind(ofFile: row.path, citedBy: context.store) {
        case .notBuilt, .current: break
        default: return nil
        }
        return context.store.usr(for: row)
    }

    /// The name a declaration's uses are matched on: an initializer's type's, since it is called through its type.
    static func searchedName(of subject: AccessSubject) -> String {
        subject.kind == .initializer ? subject.containerName ?? subject.name : CallSiteScanner.baseName(of: subject.name)
    }

    func findings(for looked: [(subject: AccessSubject, usr: String?)], semantic: SemanticInput) async throws -> [AccessFinding] {
        var uses: [Int: [AccessJudge.Use]] = [:]
        var references: [Int: [AccessExposure.Reference]] = [:]
        var shapes: [String: CallSiteScanner.SiteShape] = [:]
        for (index, entry) in looked.enumerated() {
            if let usr = entry.usr, let context = semantic.context {
                uses[index] = context.store.referenceModules(ofUSR: usr).map { AccessJudge.Use(path: context.relativePath($0.path), module: $0.module) }
                references[index] = context.store.referencePlaces(ofUSR: usr).map { AccessExposure.Reference(path: context.relativePath($0.path), line: $0.line, column: $0.column) }
            }
            let kind = entry.subject.kind
            let own: CallSiteScanner.SiteShape = kind.isTypeDeclaration || kind == .typealiasKind ? .typeUse : .of(kind, sharing: nil)
            let name = Self.searchedName(of: entry.subject)
            shapes[name] = own.widened(by: shapes[name])
        }
        let scanned = shapes.isEmpty ? [:] : await CallSiteScanner(repoRoot: repoRoot, enumerator: enumerator).callSites(named: shapes)
        let packages = AccessPackages.read(repoRoot: repoRoot, packageDirectories: resolver.packageDirectories)
        // The store answers only for the files the last build compiled as they stand: a use in any other file, in a target it left out or changed since, is matched by name and counted beside the store's.
        let coverage = semantic.context.map { OccurrenceFreshness(store: store, context: $0, projectDirectories: resolver.projectDirectories, citedBy: $0.store) }
        let uncoveredFiles = semantic.context.flatMap { context in coverage.map { covering in Set(enumerator.swiftFiles().filter { covering.kind(ofFile: $0, citedBy: context.store) != .current }) } } ?? []
        let uncoveredScanned = uncoveredFiles.count
        let exposure = AccessExposure(store: store, repoRoot: repoRoot, uncoveredFiles: uncoveredFiles)
        let implicitCallers = looked.contains { $0.subject.kind == .initializer } ? ImplicitInitializerCallers(repoRoot: repoRoot, paths: enumerator.swiftFiles(), resolver: resolver) : nil
        var testImports: [String: Set<String>?] = [:]
        var found: [AccessFinding] = []
        for (index, entry) in looked.enumerated() {
            let nameMatched = uses[index] == nil ? Self.searchedName(of: entry.subject) : nil
            let matches = (scanned[Self.searchedName(of: entry.subject)] ?? []).map { AccessJudge.Use(path: $0.path, module: resolver.resolvedModule(for: $0.path)) }
            var subjectUses = matches
            var uncovered: [String] = []
            if let resolved = uses[index], let coverage, let context = semantic.context {
                let outsideTheStore = matches.filter { coverage.kind(ofFile: $0.path, citedBy: context.store) != .current }
                subjectUses = resolved + outsideTheStore
                uncovered = Set(outsideTheStore.map(\.path)).sorted()
            }
            let module = resolver.module(for: entry.subject.path)
            // An implicit-member `init(` in another module may build any initializer of a module its file imports: where the store resolves the subject's uses, only the files it does not cover are read for one.
            if entry.subject.kind == .initializer, let implicitCallers {
                let implicit = implicitCallers.uses(ofInitializerIn: module, in: uses[index] == nil ? nil : uncoveredFiles)
                subjectUses += implicit
                if uses[index] != nil {
                    uncovered = Set(uncovered + implicit.map(\.path)).sorted()
                }
            }
            for use in subjectUses where use.module != module && testImports[use.path] == nil {
                testImports[use.path] = .some(testableImports(ofFile: use.path))
            }
            let judge = { (exposedAt: AccessLevel?) in
                AccessJudge.verdict(level: entry.subject.level, module: module, uses: subjectUses, testableImports: { testImports[$0].flatMap(\.self) }, packages: packages, exposedAt: exposedAt)
            }
            var verdict = judge(nil)
            if verdict.suggestion != nil {
                verdict = try judge(exposure.level(exposing: entry.subject, references: references[index]))
            }
            found.append(AccessFinding(subject: entry.subject, module: module, verdict: verdict, nameMatchedOn: nameMatched, nameMatchedFiles: uncovered, uncoveredFileCount: uses[index] == nil ? 0 : uncoveredScanned, published: packages.published.contains(module)))
        }
        return found
    }

    /// The modules a test file imports `@testable`, and `nil` for a file that is no test file.
    func testableImports(ofFile path: String) -> Set<String>? {
        guard let source = try? String(contentsOf: repoRoot.appending(path: path), encoding: .utf8),
              TestFileRecognition.isTestFile(imports: ImportLineReader.modules(inSource: source)) else { return nil }
        return Set(ImportLineReader.testableModules(inSource: source))
    }
}
