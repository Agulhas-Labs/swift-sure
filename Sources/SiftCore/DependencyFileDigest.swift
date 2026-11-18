//
// Copyright © Agulhas Labs
//

import Foundation

/// A file inside a resolved package's checkout, named explicitly to `digest`, parsed on demand and answered as a file digest.
///
/// Nothing is written to the repository's index: the file is parsed into a store held in memory for this one answer, so no later `where`, `search` or digest of the repository sees it.
struct DependencyFileDigest {
    let renderer: DigestRenderer

    /// The checkout directories a dependency's sources are resolved into, below the repository root.
    private static let checkoutParents = [[".build", "checkouts"], ["SourcePackages", "checkouts"]]

    /// The answer for `target` where it names a Swift file inside a resolved package's checkout, or `nil` for any other target, which keeps its usual answer.
    func answer(target: String, options: DigestOptions) throws -> MeasuredAnswer? {
        let range = DigestLineRange.parse(target)
        let path = range?.path ?? target
        guard path.hasSuffix(".swift"), path.contains("checkouts/"),
              let (relative, package) = checkoutFile(named: path) else { return nil }
        let store = try IndexStore(databasePath: IndexStore.inMemoryPath)
        guard let parsed = FileParser.parse(absoluteURL: renderer.repoRoot.appendingPathComponent(relative), repoRelativePath: relative) else { return nil }
        try store.replaceFiles([parsed]) { _ in (module: package, guessed: false) }
        var scoped = try DigestRenderer(store: store, moduleNames: store.moduleNames(), repoRoot: renderer.repoRoot)
        scoped.config = renderer.config
        let answer = if let range {
            try scoped.renderFileRange(DigestLineRange(path: relative, start: range.start, end: range.end, suffix: range.suffix), options: options)
        } else {
            try scoped.renderFile(path: relative, options: options)
        }
        let marker = "\(relative) (dependency \(package)\(version(of: package).map { " " + $0 } ?? "")) — read on demand, not indexed"
        return MeasuredAnswer(text: marker + "\n" + answer.text, bytes: answer.bytes, missed: answer.missed)
    }

    /// The repo-relative path of the file `path` names and the package whose checkout holds it, or `nil` where it is not a file inside one.
    ///
    /// Judged on the path with every `..` and symbolic link resolved, so a path that leaves the checkout, or a link pointing out of it, is not a dependency's file.
    private func checkoutFile(named path: String) -> (relative: String, package: String)? {
        let root = renderer.repoRoot.resolvingSymlinksInPath().path
        let candidates = path.hasPrefix("/") ? [URL(fileURLWithPath: path)] : [renderer.repoRoot, renderer.currentDirectory].map { $0.appendingPathComponent(path) }
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath().path
            var isDirectory: ObjCBool = false
            guard resolved.hasPrefix(root + "/"),
                  FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let relative = String(resolved.dropFirst(root.count + 1))
            let components = relative.split(separator: "/").map(String.init)
            for parent in Self.checkoutParents where components.count > parent.count + 1 && Array(components.prefix(parent.count)) == parent {
                return (relative, components[parent.count])
            }
        }
        return nil
    }

    /// The version `Package.resolved` pins `package` at, or `nil` where the file, the pin or its version cannot be read.
    ///
    /// Both the identity-keyed formats (versions 2 and 3) and the older package-keyed one (version 1) are read; a pin is matched by the identity, or the last component of its location or repository URL, written in lowercase.
    private func version(of package: String) -> String? {
        guard let data = try? Data(contentsOf: renderer.repoRoot.appendingPathComponent("Package.resolved")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let pins = (root["pins"] as? [[String: Any]]) ?? ((root["object"] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []
        let wanted = package.lowercased()
        for pin in pins {
            let names = ["identity", "package"].compactMap { (pin[$0] as? String)?.lowercased() }
                + ["location", "repositoryURL"].compactMap { (pin[$0] as? String).map(Self.repositoryName(of:)) }
            if names.contains(wanted), let version = (pin["state"] as? [String: Any])?["version"] as? String {
                return version
            }
        }
        return nil
    }

    private static func repositoryName(of location: String) -> String {
        let last = location.split(separator: "/").last.map(String.init) ?? location
        return (last.hasSuffix(".git") ? String(last.dropLast(4)) : last).lowercased()
    }
}
