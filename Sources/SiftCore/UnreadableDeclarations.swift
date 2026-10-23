//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// Why the project's declarations could not be read, in the words the devices line prints inside parentheses.
public struct UnreadableDeclarations: Error, Equatable, Sendable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}
