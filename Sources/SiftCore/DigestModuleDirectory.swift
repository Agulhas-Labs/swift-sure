//
// Copyright © Agulhas Labs
//

import Foundation

/// The module a directory target names: the one module whose indexed files are exactly the directory's.
struct DigestModuleDirectory {
    let renderer: DigestRenderer

    /// The module's answer when the target is its source directory, or `nil` when the target names no such directory.
    func answer(for target: String, options: DigestOptions) throws -> MeasuredAnswer? {
        let written = target.hasSuffix("/") ? String(target.dropLast()) : target
        let directory = renderer.relativeToRepository(written) ?? written
        let files = try renderer.store.fileInventory().values.map { (path: $0.path, module: $0.module) }
        guard let module = Self.module(of: directory, files: files) else { return nil }
        return try MeasuredAnswer(text: renderer.renderModule(module, options: options))
    }

    /// The module owning every file under `directory` and nothing outside it, or `nil` when the directory holds no file, several modules, or only part of one.
    static func module(of directory: String, files: [(path: String, module: String)]) -> String? {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        let inside = files.filter { $0.path.hasPrefix(prefix) }
        guard let module = inside.first?.module, inside.allSatisfy({ $0.module == module }) else { return nil }
        return files.contains { $0.module == module && !$0.path.hasPrefix(prefix) } ? nil : module
    }
}
