//
// Copyright © Agulhas Labs
//

import Foundation

/// The SwiftPM packages a repository holds, as `diff`'s access section needs them: which package each target belongs to, each package's tools-version, and the targets its library products publish.
struct AccessPackages: Sendable {
    /// Each SwiftPM target's package, by the repo-relative directory of its `Package.swift`.
    var packageOf: [String: String] = [:]
    var toolsVersion: [String: [Int]] = [:]
    var published: Set<String> = []

    /// The manifests in `packageDirectories` (repo-relative, the root as the empty string), read syntactically.
    static func read(repoRoot: URL, packageDirectories: [String]) -> AccessPackages {
        var packages = AccessPackages()
        for directory in packageDirectories {
            let base = directory.isEmpty ? repoRoot : repoRoot.appending(path: directory)
            let manifest = SwiftPMManifest.parse(fileAt: base.appending(path: "Package.swift"))
            for target in manifest.targets {
                packages.packageOf[target.name] = directory
            }
            packages.toolsVersion[directory] = manifest.toolsVersion
            packages.published.formUnion(manifest.libraryTargets)
        }
        return packages
    }

    /// Whether `package` would serve every one of `users` from `module`: all of them targets of the declaring module's own `Package.swift`, whose tools-version is at least 5.9, the first to pass `-package-name`.
    func allowsPackage(declaring module: String, users: Set<String>) -> Bool {
        guard let home = packageOf[module], let version = toolsVersion[home], !version.lexicographicallyPrecedes([5, 9]) else { return false }
        return users.allSatisfy { packageOf[$0] == home }
    }
}
