//
// Copyright © Agulhas Labs
//

import Foundation

/// The module a directory target names: the one module whose indexed files are the directory's, served whole when they are all of it and as a folder slice when they are part of it.
struct DigestModuleDirectory {
    let renderer: DigestRenderer

    /// The module's answer when the target is its source directory, or the folder slice when it holds only part of one module; `nil` when the target names no such directory.
    func answer(for target: String, options: DigestOptions) throws -> MeasuredAnswer? {
        let written = target.hasSuffix("/") ? String(target.dropLast()) : target
        let directory = renderer.relativeToRepository(written) ?? written
        let files = try renderer.store.fileInventory().values.map { (path: $0.path, module: $0.module) }
        guard let module = Self.module(of: directory, files: files) else { return nil }
        guard !Self.holdsWholeModule(module, directory: directory, files: files) else {
            return try MeasuredAnswer(text: renderer.renderModule(module, options: options))
        }
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        let name = directory.split(separator: "/").last.map(String.init) ?? directory
        return try MeasuredAnswer(text: renderer.renderModule(module, folder: (name: name, prefix: prefix), options: options))
    }

    /// The one module owning every file under `directory`, or `nil` when the directory holds no file or several modules.
    static func module(of directory: String, files: [(path: String, module: String)]) -> String? {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        let inside = files.filter { $0.path.hasPrefix(prefix) }
        guard let module = inside.first?.module, inside.allSatisfy({ $0.module == module }) else { return nil }
        return module
    }

    /// Whether no file of `module` lies outside `directory`, so the directory is the module's own source directory rather than a folder in it.
    static func holdsWholeModule(_ module: String, directory: String, files: [(path: String, module: String)]) -> Bool {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return !files.contains { $0.module == module && !$0.path.hasPrefix(prefix) }
    }
}
