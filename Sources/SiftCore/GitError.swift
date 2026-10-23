//
// Copyright © Agulhas Labs
//

import Foundation

/// A failed git invocation, carrying git's own stderr.
public struct GitError: Error, CustomStringConvertible, Sendable {
    public let message: String
    /// What git itself printed on stderr, trimmed — the wording a refusal quotes when the fault is in what the caller asked git for.
    public var detail = ""
    /// The bound git was held to, where it failed for want of an answer within it rather than by answering.
    public var unansweredWithin: TimeInterval?

    public var description: String {
        message
    }
}
