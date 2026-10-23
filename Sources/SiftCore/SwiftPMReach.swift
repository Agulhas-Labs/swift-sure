//
// Copyright © Agulhas Labs
//

import Foundation

/// Which SwiftPM targets can reach which, read from the dependency lists of the manifests found.
///
/// Only a ruling out is answered: a pair is unreachable when both targets belong to one readable manifest and the second is outside the first's transitive dependencies. Everything the manifests cannot settle (a target in no manifest or in several, targets of different manifests, a computed name, a `.dependencies` list changed outside a target declaration, a `Package@swift-*.swift` beside the manifest, a dependency on another package's product, an unreadable dependency) is reachable.
struct SwiftPMReach {
    private let packages: [Package]

    /// The graph of every manifest in `manifests`, targets by the module name the build spells.
    init(manifests: [SwiftPMManifest]) {
        packages = manifests.map(Package.init(manifest:))
    }

    /// Whether code in module `from` may name types of module `to`; `true` unless the manifests rule it out.
    func canReach(from: String?, to: String) -> Bool {
        guard let from else { return true }
        let sources = packages.indices.filter { packages[$0].edges[from] != nil }
        let destinations = packages.indices.filter { packages[$0].edges[to] != nil }
        guard sources.count == 1, sources == destinations else { return true }
        return packages[sources[0]].reaches(from: from, to: to)
    }
}

extension SwiftPMReach {
    /// One manifest's targets, each with the targets it depends on directly.
    struct Package {
        var edges: [String: Set<String>] = [:]
        /// Targets whose dependencies are not all readable.
        var open: Set<String> = []
        /// Whether the manifest computes a target name, changes a `.dependencies` list outside a target declaration, or has a `Package@swift-*.swift` beside it, so what it states is partial.
        var everythingOpen = false

        init(manifest: SwiftPMManifest) {
            let names = Set(manifest.targets.map { C99ExtendedIdentifier.spelling(of: $0.name) })
            for target in manifest.targets {
                let name = C99ExtendedIdentifier.spelling(of: target.name)
                var direct = edges[name] ?? []
                for dependency in target.dependencies {
                    let spelled = C99ExtendedIdentifier.spelling(of: dependency)
                    if names.contains(spelled) {
                        direct.insert(spelled)
                    } else if let products = manifest.libraryProducts[dependency] {
                        direct.formUnion(products.map(C99ExtendedIdentifier.spelling(of:)))
                    } else {
                        open.insert(name)
                    }
                }
                for product in target.products {
                    if let products = manifest.libraryProducts[product] {
                        direct.formUnion(products.map(C99ExtendedIdentifier.spelling(of:)))
                    } else {
                        open.insert(name)
                    }
                }
                if target.unreadableDependencies {
                    open.insert(name)
                }
                edges[name] = direct
            }
            everythingOpen = manifest.computedTargetNames || manifest.changesDependenciesOutsideDeclarations || manifest.hasVersionSpecificManifest
        }

        /// Whether `to` is among the transitive dependencies of `from`, or any target on the way is open.
        func reaches(from: String, to: String) -> Bool {
            if everythingOpen {
                return true
            }
            var seen: Set<String> = [from]
            var pending = [from]
            while let next = pending.popLast() {
                if open.contains(next) {
                    return true
                }
                for dependency in edges[next] ?? [] where seen.insert(dependency).inserted {
                    pending.append(dependency)
                }
            }
            return seen.contains(to)
        }
    }
}
