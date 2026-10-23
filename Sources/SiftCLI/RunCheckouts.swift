//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SiftCore

/// The checkout `swift-sure run` was started in and the one its command builds, which a `--package-path`, `-C` or `-project` naming another repository makes two.
///
/// Read by ``RunCommandKind/builtDirectory(of:from:)``, the reading the stop gate's transcript reader places a run by, so the run and the gate agree on which checkout it built.
struct RunCheckouts {
    /// The repository `swift-sure run` was started in, `nil` outside one.
    let launched: URL?
    /// The directory the command reads its project from — `nil` where a flag spells it through a variable.
    let builtDirectory: String?
    /// The repository the command builds: ``launched`` unless a flag names a directory in another, and `nil` where that is spelled through a variable or lies in no repository.
    let built: URL?

    /// Throws ``EngineError/gitDidNotAnswer(_:seconds:)`` where git does not answer for the directory the command builds: which checkout that is is then not known.
    init(arguments: [String], workingDirectory: URL, launched: URL?) throws {
        self.launched = launched
        builtDirectory = RunCommandKind.builtDirectory(of: arguments, from: workingDirectory.path)
        built = try builtDirectory.flatMap { $0 == workingDirectory.path ? launched : try GitContext.enclosingRoot(from: URL(fileURLWithPath: $0)) }
    }

    /// Whether the command builds a checkout other than ``launched``, or one nobody can name: a build of a sibling package says nothing about the tree `swift-sure run` was started in.
    var buildsElsewhere: Bool {
        built.map { CanonicalPath.of($0.path) } != launched.map { CanonicalPath.of($0.path) }
    }

    /// Why `--without` or `--without-line` refuses this command, or `nil` where it builds the checkout the change is set aside from.
    ///
    /// Refused rather than followed: the pathspec names files in the checkout `swift-sure run` was started in, and setting them aside proves nothing about a command that builds another one.
    func setAsideRefusal(flag: String) -> String? {
        guard buildsElsewhere else {
            return nil
        }
        let reads = builtDirectory.map { "builds \($0)" } ?? "names the directory it builds through a variable"
        return "\(ProductName.current.binary) run \(flag): the command \(reads), not the checkout the change is set aside from — run it in the checkout it builds, with \(ProductName.current.binary) run --root naming that checkout."
    }
}
