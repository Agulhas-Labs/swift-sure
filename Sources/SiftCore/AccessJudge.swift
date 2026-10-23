//
// Copyright © Agulhas Labs
//

/// Decides one declaration's access verdict from the uses found for it: the narrowest level those uses allow, with `internal` as the floor.
struct AccessJudge {
    /// The verdict for a declaration at `level` in `module`.
    ///
    /// `testableImports` gives, for a test file, the modules it imports `@testable`, and `nil` for any other file. `exposedAt` is the widest level of a declaration that names this one in its head or an `@inlinable` body, which no suggestion goes below.
    static func verdict(level: AccessLevel, module: String, uses: [Use], testableImports: (String) -> Set<String>?, packages: AccessPackages, exposedAt: AccessLevel?) -> AccessFinding.Verdict {
        let outside = uses.filter { $0.module != module }
        let production = outside.filter { testableImports($0.path)?.contains(module) != true }
        let verdict: AccessFinding.Verdict = if outside.isEmpty {
            .noUse(testable: false)
        } else if production.isEmpty {
            .noUse(testable: true)
        } else if level == .publicLevel, production.allSatisfy({ $0.module != nil }),
                  packages.allowsPackage(declaring: module, users: Set(production.compactMap(\.module)))
        {
            .packageOnly(users: Set(production.compactMap(\.module)).sorted())
        } else {
            .needsLevel
        }
        if let exposedAt, let suggestion = verdict.suggestion, exposedAt > suggestion {
            return .needsLevel
        }
        return verdict
    }
}

extension AccessJudge {
    /// One place the declaration is used: its repo-relative file and the module that file compiles into, `nil` where that module is unknown, which counts as outside every module.
    struct Use: Sendable, Equatable {
        let path: String
        let module: String?
    }
}
