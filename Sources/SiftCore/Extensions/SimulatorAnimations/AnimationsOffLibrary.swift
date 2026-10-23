//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorAnimations

/// The animations-off library is swift-fieldwork's (`SimulatorAnimations`); SwiftSure names the variable that keeps animations on and the directory the compiled copy is cached in.
extension AnimationsOffLibrary {
    /// SwiftSure's library: `SWIFT_SURE_ANIMATIONS` is the variable it reads, and `<home>/libraries` beside the rest of SwiftSure's per-user state is where it is kept.
    ///
    /// Throws ``AnimationsOffError/libraryNotBuilt(_:)`` where the variable name is refused.
    static func sift(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AnimationsOffLibrary {
        do {
            return try AnimationsOffLibrary(
                environmentVariable: EnvironmentVariable.animations.name,
                directory: SiftPaths.home(environment: environment).appendingPathComponent("libraries", isDirectory: true)
            )
        } catch let error as AnimationsOffLibraryError {
            throw AnimationsOffError.libraryNotBuilt(String(describing: error))
        }
    }

    /// The library's path, compiled first when that file is absent; a failure is ``AnimationsOffError/libraryNotBuilt(_:)`` carrying the compiler's first line of complaint.
    func builtForSift(compile: Compile = { try Subprocess.run($0, $1, deadline: 120) }) throws -> URL {
        do {
            return try built(compile: compile)
        } catch let AnimationsOffLibraryError.notBuilt(reason) {
            throw AnimationsOffError.libraryNotBuilt(reason)
        }
    }
}
