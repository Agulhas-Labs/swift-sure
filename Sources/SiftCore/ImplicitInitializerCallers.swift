//
// Copyright © Agulhas Labs
//

import Foundation

/// The Swift files that call an initializer by implicit member anywhere in their text, each with its module, read once per answer.
///
/// Which type such a call builds cannot be told without types, and a file reaches a type without importing its module (a re-export, a value another module returns), so a file of another module counts as a use of every initializer of each module it imports, and of each module the build files do not rule out.
struct ImplicitInitializerCallers {
    let callers: [Caller]
    private let reach: SwiftPMReach

    /// The files among `paths`, repository-relative, whose text calls `init(` by implicit member, each read once.
    init(repoRoot: URL, paths: [String], resolver: ModuleResolver) {
        reach = resolver.reach
        callers = paths.compactMap { path in
            guard let source = try? String(contentsOf: repoRoot.appending(path: path), encoding: .utf8), AccessExposure.callsImplicitInit(source) else { return nil }
            return Caller(use: AccessJudge.Use(path: path, module: resolver.resolvedModule(for: path)), imports: Set(ImportLineReader.modules(inSource: source)))
        }
    }

    /// The uses of an initializer declared in `module`: each caller of another module that imports it or that the build files do not rule out from reaching it, among `files`, or among every caller where that is `nil`.
    func uses(ofInitializerIn module: String, in files: Set<String>?) -> [AccessJudge.Use] {
        callers.filter { $0.use.module != module && ($0.imports.contains(module) || reach.canReach(from: $0.use.module, to: module)) && files?.contains($0.use.path) ?? true }.map(\.use)
    }
}

extension ImplicitInitializerCallers {
    /// One file calling an initializer by implicit member.
    struct Caller {
        let use: AccessJudge.Use
        /// The modules the file imports.
        let imports: Set<String>
    }
}
